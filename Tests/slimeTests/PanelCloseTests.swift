import AppKit
import Testing
@testable import slime

private actor CloseGate {
  private var continuation: CheckedContinuation<WindowCloseResult, Never>?
  private(set) var calls = 0
  private var earlyResult: WindowCloseResult?
  private var started: CheckedContinuation<Void, Never>?
  func close(_ window: Window) async -> WindowCloseResult {
    calls += 1
    started?.resume(); started = nil
    if let earlyResult { return earlyResult }
    return await withCheckedContinuation { continuation = $0 }
  }
  func waitUntilStarted() async {
    guard calls == 0 else { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish(_ result: WindowCloseResult) { earlyResult = result; continuation?.resume(returning: result); continuation = nil }
}

@MainActor private func controller(_ gate: CloseGate) -> PanelController {
  _ = NSApplication.shared
  let panel = PanelController(closeWindow: { window, _ in await gate.close(window) })
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.setWindows((1...3).map {
    Window(pid: 1, windowID: UInt32($0), appName: "Test", title: "Window \($0)", isMinimized: false)
  })
  return panel
}

@Test @MainActor func closeWaitsForConfirmationAndSelectsNextNeighbor() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  var prematurelyFinished = false
  panel.onCloseFinished = { prematurelyFinished = true }
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  await gate.waitUntilStarted()
  #expect(await gate.calls == 1)
  #expect(!prematurelyFinished)
  #expect(panel.rows.map(\.windowID) == [1, 2, 3])
  #expect(panel.closing)
  let card = try #require(panel.panel.content.gridView.card(for: 1))
  #expect(card.layer?.backgroundColor == NSColor.clear.cgColor)
  #expect(card.subviews.compactMap { $0 as? NSTextField }.first?.alphaValue == 0)
  #expect(panel.panel.content.gridView.subviews.first { $0 is HighlightView }?.alphaValue == 0)
  await gate.finish(.closed)
  for _ in 0..<100 where panel.closing { try await Task.sleep(for: .milliseconds(20)) }
  #expect(panel.rows.map(\.windowID) == [2, 3])
  #expect(panel.rows[panel.selection].windowID == 2)
  #expect(!panel.closing)
}

@Test @MainActor func failedCloseRestoresTheTarget() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  try await Task.sleep(for: .milliseconds(30))
  await gate.finish(.failed)
  for _ in 0..<100 where panel.closing { try await Task.sleep(for: .milliseconds(20)) }
  #expect(panel.rows.map(\.windowID) == [1, 2, 3])
  #expect(panel.selection == 0)
  let card = try #require(panel.panel.content.gridView.card(for: 1))
  #expect(card.subviews.compactMap { $0 as? NSTextField }.first?.alphaValue == 1)
  #expect(panel.panel.content.gridView.subviews.first { $0 is HighlightView }?.alphaValue == 1)
  #expect(panel.panel.content.gridView.card(for: 1)?.preview.layer?.opacity == 1)
  #expect(!panel.panel.content.statusLabel.stringValue.isEmpty)
}

@Test @MainActor func dismissedCloseCannotRewriteANewSession() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  var completed = false
  var observedClose = false
  panel.onClosed = { _, _ in observedClose = true }
  panel.onCloseFinished = { completed = true }
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  try await Task.sleep(for: .milliseconds(30))
  panel.dismiss()
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.setWindows([Window(pid: 1, windowID: 9, appName: "New", title: "New", isMinimized: false)])
  await gate.finish(.closed)
  for _ in 0..<100 where !observedClose { try await Task.sleep(for: .milliseconds(20)) }
  #expect(observedClose)
  #expect(panel.rows.map(\.windowID) == [9])
  #expect(!completed)
}

@Test @MainActor func closingLastWindowSelectsPreviousAndEmptyCloseCompletes() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  panel.handle(state: .lingering(query: "", selection: 2), effects: [.moveSelection(axis: .horizontal, step: -1)])
  #expect(panel.selection == 2)
  panel.handle(state: .closing(query: "", selection: 2), effects: [.closeWindow])
  await gate.finish(.closed)
  for _ in 0..<100 where panel.closing { try await Task.sleep(for: .milliseconds(20)) }
  #expect(panel.rows.map(\.windowID) == [1, 2])
  #expect(panel.rows[panel.selection].windowID == 2)
  panel.setWindows([])
  var finished = false
  panel.onCloseFinished = { finished = true }
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  #expect(finished)
  #expect(!panel.closing)
  #expect(panel.rows.isEmpty)
}

@Test @MainActor func closingFollowsTheNextSurvivingNeighborAcrossRefresh() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  let windows = (1...5).map { Window(pid: 1, windowID: UInt32($0), appName: "Test", title: "\($0)", isMinimized: false) }
  panel.setWindows(windows)
  panel.handle(state: .lingering(query: "", selection: 1), effects: [.moveSelection(axis: .horizontal, step: 1)])
  panel.handle(state: .closing(query: "", selection: 1), effects: [.closeWindow])
  panel.setWindows(Array(windows.suffix(2)))
  await gate.finish(.closed)
  for _ in 0..<100 where panel.closing { try await Task.sleep(for: .milliseconds(20)) }
  #expect(panel.rows[panel.selection].windowID == 4)
}

@Test @MainActor func inaccessibleCloseRevealsTargetAndDoesNotReopenPanel() async throws {
  _ = NSApplication.shared
  let gate = CloseGate()
  var revealed: UInt32?
  var cancelled = false
  let panel = PanelController(closeWindow: { window, _ in await gate.close(window) }, revealWindow: { window, request in
    #expect(request.isActive)
    revealed = window.windowID
    return true
  })
  panel.onCancelSession = { cancelled = true }
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.setWindows([Window(pid: 1, windowID: 7, appName: "Test", title: "Target", isMinimized: false)])
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  await gate.finish(.unavailable)
  for _ in 0..<100 where !cancelled { try await Task.sleep(for: .milliseconds(20)) }
  #expect(revealed == 7)
  #expect(cancelled)
  #expect(!panel.panel.isVisible)
  for _ in 0..<100 where await gate.calls < 2 { try await Task.sleep(for: .milliseconds(20)) }
  #expect(await gate.calls == 2)
}

@Test @MainActor func cancellingCloseStopsItsRequestAndCannotStartAnotherUntilItReturns() async throws {
  let gate = CloseGate()
  let panel = PanelController(closeWindow: { window, request in
    #expect(request.isActive)
    let result = await gate.close(window)
    #expect(!request.isActive)
    return result
  })
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.setWindows([Window(pid: 1, windowID: 7, appName: "Test", title: "Target", isMinimized: false)])
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  await gate.waitUntilStarted()
  panel.dismiss()
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  #expect(await gate.calls == 1)
  await gate.finish(.failed)
}

@Test @MainActor func intentionalHandoffDoesNotCancelItsOwnRequestOrPressAgainForASheet() async throws {
  _ = NSApplication.shared
  var revealCount = 0
  let gate = CloseGate()
  let panel = PanelController(closeWindow: { window, _ in await gate.close(window) }, revealWindow: { _, request in
    #expect(request.isActive)
    revealCount += 1
    return true
  })
  // orderOut may deliver resignKey synchronously or after cancelling the tap session.
  var resigned = false
  panel.onCancelSession = {
    if !resigned { resigned = true; panel.panel.resignKey() }
  }
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.setWindows([Window(pid: 1, windowID: 7, appName: "Test", title: "Target", isMinimized: false)])
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  await gate.finish(.confirmationRequired)
  for _ in 0..<100 where revealCount == 0 { try await Task.sleep(for: .milliseconds(20)) }
  #expect(revealCount == 1)
  #expect(await gate.calls == 1)
  #expect(!panel.panel.isVisible)
  panel.onCancelSession = nil
}

@Test @MainActor func themeChangeDuringClosePreservesTheTransaction() async throws {
  _ = NSApplication.shared
  let suite = "slime.close-theme.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let gate = CloseGate()
  let controller = PanelController(settings: settings, closeWindow: { window, _ in await gate.close(window) })
  controller.handle(state: .lingering(query: "", selection: 0), effects: [])
  controller.setWindows((1...2).map { Window(pid: 1, windowID: UInt32($0), appName: "Test", title: "Window", isMinimized: false) })
  controller.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  await gate.waitUntilStarted()
  let originalCard = controller.panel.content.gridView.card(for: 1)
  settings.panelBackground = .white
  controller.refreshAppearance()
  #expect(controller.closing)
  #expect(controller.panel.content.gridView.card(for: 1) === originalCard)
  #expect(controller.panel.content.gridView.subviews.first { $0 is HighlightView }?.alphaValue == 0)
  #expect(await gate.calls == 1)
  await gate.finish(.closed)
  for _ in 0..<100 where controller.closing { try await Task.sleep(for: .milliseconds(20)) }
  #expect(controller.rows.map(\.windowID) == [2])
  #expect(!controller.closing)
  controller.dismiss()
}
