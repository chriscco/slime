import AppKit
import Testing
@testable import slime

private actor CloseGate {
  private var continuation: CheckedContinuation<WindowCloseResult, Never>?
  private(set) var calls = 0
  private var earlyResult: WindowCloseResult?
  func close(_ window: Window) async -> WindowCloseResult {
    calls += 1
    if let earlyResult { return earlyResult }
    return await withCheckedContinuation { continuation = $0 }
  }
  func finish(_ result: WindowCloseResult) { earlyResult = result; continuation?.resume(returning: result); continuation = nil }
}

@MainActor private func controller(_ gate: CloseGate) -> PanelController {
  _ = NSApplication.shared
  let panel = PanelController(closeWindow: { await gate.close($0) })
  panel.handle(state: .lingering(query: "", selection: 0), effects: [])
  panel.setWindows((1...3).map {
    Window(pid: 1, windowID: UInt32($0), appName: "Test", title: "Window \($0)", isMinimized: false)
  })
  return panel
}

@Test @MainActor func closeWaitsForConfirmationAndSelectsNextNeighbor() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  panel.handle(state: .closing(query: "", selection: 0), effects: [.closeWindow])
  try await Task.sleep(for: .milliseconds(500))
  #expect(await gate.calls == 1)
  #expect(panel.rows.map(\.windowID) == [1, 2, 3])
  #expect(panel.closing)
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
  await gate.finish(.stillOpen)
  for _ in 0..<100 where panel.closing { try await Task.sleep(for: .milliseconds(20)) }
  #expect(panel.rows.map(\.windowID) == [1, 2, 3])
  #expect(panel.selection == 0)
  #expect(panel.panel.content.gridView.card(for: 1)?.preview.layer?.opacity == 1)
  #expect(!panel.panel.content.statusLabel.stringValue.isEmpty)
}

@Test @MainActor func dismissedCloseCannotRewriteANewSession() async throws {
  let gate = CloseGate()
  let panel = controller(gate)
  var completed = false
  var observedClose = false
  panel.onClosed = { _ in observedClose = true }
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
