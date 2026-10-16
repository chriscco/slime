import AppKit

/// The tap owns keyboard state; the controller owns window identity and layout.
@MainActor
final class PanelController {
  var onActivate: ((Window) -> Void)?
  var onRefresh: (() -> Void)?
  var onOpenSettings: (() -> Void)?
  var onClosed: ((Window, [Window]) -> Void)?
  var onCloseFinished: (() -> Void)?
  var onCancelSession: (() -> Void)?
  let panel = PanelWindow()
  private let settings: Settings
  private let closeWindow: @Sendable (Window, AXRequest) async -> WindowCloseResult
  private let revealWindow: @MainActor (Window, AXRequest) async -> Bool
  private var closeRequest: AXRequest?
  private var windows: [Window] = []
  private var nextWindows: [Window] = []
  private(set) var rows: [Window] = []
  private(set) var selection = 0
  private var query = ""
  private var phase: State = .idle
  private var session = 0
  private(set) var closing = false
  private var gridLayout = GridLayout(count: 0)

  init(settings: Settings = Settings(),
       closeWindow: @escaping @Sendable (Window, AXRequest) async -> WindowCloseResult = { await WindowActivator.close($0, request: $1) },
       revealWindow: @escaping @MainActor (Window, AXRequest) async -> Bool = { await WindowActivator.revealForClosing($0, request: $1) }) {
    self.settings = settings
    self.closeWindow = closeWindow
    self.revealWindow = revealWindow
    panel.onResignKey = { [weak self] in
      guard let self, self.phase.isSessionOpen else { return }
      self.dismiss()
    }
    WindowThumbnails.onChange = { [weak self] in
      guard let self, self.phase.isSessionOpen, !self.closing else { return }
      self.panel.content.gridView.rows = self.rows
    }
  }

  func handle(state: State, effects: [Effect]) {
    phase = state
    for effect in effects {
      switch effect {
      case .passThrough, .swallow, .cancel: break
      case .showPanel: show()
      case .hidePanel: hide()
      case .openSettings: hide(); onOpenSettings?()
      case .closeWindow: beginClose()
      case .activate:
        if !closing, rows.indices.contains(selection) { onActivate?(rows[selection]) }
      case .moveSelection(let axis, let step):
        guard !closing, !rows.isEmpty else { continue }
        selection = Self.movedSelection(from: selection, axis: axis, step: step, layout: gridLayout)
        panel.content.gridView.setSelection(selection, animated: true)
        panel.content.gridView.scrollSelectionToVisible()
      case .appendQuery(let character):
        guard !closing else { continue }
        panel.content.setSearchFocused(true)
        query.append(character); selection = 0; rerank(following: nil)
      case .deleteQueryChar:
        guard !closing else { continue }
        query = String(query.dropLast()); selection = 0; rerank(following: nil)
      case .focusSearchField:
        panel.content.setSearchFocused(true)
      }
    }
  }

  func setWindows(_ windows: [Window]) {
    nextWindows = windows
    guard phase.isSessionOpen, !closing else { self.windows = windows; return }
    let fresh = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
    let existing = Set(self.windows.map(\.windowID))
    self.windows = self.windows.compactMap { fresh[$0.windowID] } + windows.filter { !existing.contains($0.windowID) }
    rerank(following: rows.indices.contains(selection) ? rows[selection].windowID : nil)
  }

  func refreshAppearance() {
    panel.content.accentColor = settings.highlightColor
    panel.applyGlassSettings(settings)
    if panel.content.gridView.highlightColor != settings.highlightColor {
      panel.content.gridView.highlightColor = settings.highlightColor
    }
  }

  private func show() {
    closeRequest?.cancel()
    session += 1
    closing = false
    let previous = nextWindows.dropFirst().first?.windowID ?? nextWindows.first?.windowID
    windows = settings.groupByApp ? WindowCache.sort(nextWindows, byMRU: []) : nextWindows
    query = ""; selection = 0
    panel.content.showStatus(nil)
    panel.content.setSearchFocused(false)
    refreshAppearance()
    WindowThumbnails.beginSession(source: settings.previewSource)
    if settings.previewSource == .fresh { WindowThumbnails.warm(windows) }
    rerank(following: previous)
    let generation = session
    var presented = false
    let present: @MainActor @Sendable () -> Void = { [weak self] in
      guard let self, !presented, self.session == generation, self.phase.isSessionOpen else { return }
      presented = true
      self.panel.makeKeyAndOrderFront(nil)
    }
    if WindowThumbnails.hasPendingWork {
      WindowThumbnails.whenSettled(present)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: present)
    } else { present() }
    onRefresh?()
  }

  private func hide(cancelClose: Bool = true) {
    WindowThumbnails.endSession()
    panel.content.gridView.releaseRetainedCards()
    if cancelClose { closeRequest?.cancel() }
    session += 1
    closing = false
    for row in rows { panel.content.gridView.card(for: row.windowID)?.preview.restore() }
    panel.content.gridView.setClosing(nil)
    panel.content.setSearchFocused(false)
    panel.orderOut(nil)
  }

  func dismiss() {
    phase = .idle
    hide()
    onCancelSession?()
  }

  static func movedSelection(from selection: Int, axis: Axis, step: Int, layout: GridLayout) -> Int {
    layout.movedSelection(from: selection, axis: axis, step: step)
  }

  private func rerank(following id: UInt32?, animateResize: Bool = false) {
    panel.content.gridView.retainCards(for: windows)
    let previousRows = rows
    rows = Search.rank(windows, query: query)

    if let id { selection = rows.firstIndex { $0.windowID == id } ?? 0 }
    else { selection = min(max(selection, 0), max(0, rows.count - 1)) }
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    let available = screen.map { Double($0.visibleFrame.width - 40) }
    let starts = settings.groupByApp ? rows.indices.filter { $0 == 0 || rows[$0].pid != rows[$0 - 1].pid } : []
    gridLayout = GridLayout(count: rows.count, groupStarts: starts, availableWidth: available)
    let size = NSSize(width: gridLayout.panelWidth,
      height: min(gridLayout.panelHeight, screen.map { $0.visibleFrame.height - 40 } ?? gridLayout.panelHeight))
    var target = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
    if let screen {
      target.origin = NSPoint(x: screen.visibleFrame.midX - target.width / 2,
        y: screen.visibleFrame.midY - target.height / 2)
    } else { target.origin = panel.frame.origin }
    if panel.frame != target {
      if animateResize && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.2
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          panel.animator().setFrame(target, display: true)
        }
      } else { panel.setFrame(target, display: true) }
    }
    panel.layoutIfNeeded()
    let content = panel.content
    content.gridView.groupByApp = settings.groupByApp
    content.gridView.availableWidth = available
    content.setSearchText(query)
    content.emptyLabel.stringValue = localized("No windows", "没有窗口")
    content.emptyLabel.isHidden = !rows.isEmpty
    if previousRows != rows { content.render(rows: rows) }
    else { content.layoutSubtreeIfNeeded() }
    content.gridView.setSelection(selection, animated: false)
    content.gridView.scrollSelectionToVisible()
  }

  private func beginClose() {
    guard !closing else { return }
    guard closeRequest == nil else { onCloseFinished?(); return }
    guard rows.indices.contains(selection) else { onCloseFinished?(); return }
    let target = rows[selection]
    let siblings = windows.filter { $0.pid == target.pid }
    let neighbors = Array(rows.dropFirst(selection + 1)) + rows.prefix(selection).reversed()
    let generation = session
    let preview = panel.content.gridView.card(for: target.windowID)?.preview
    closing = true
    panel.content.gridView.setClosing(target.windowID)
    panel.content.showStatus(localized("Closing window…", "正在关闭窗口…"))
    let request = AXRequest(seconds: 3)
    closeRequest = request
    let operation = closeWindow
    Task { [weak self] in
      async let result = operation(target, request)
      await preview?.animateClose()
      var outcome = await result
      guard let self else { return }
      defer { self.closeRequest = nil }
      if (outcome == .unavailable || outcome == .confirmationRequired), request.isActive,
         self.session == generation, self.phase.isSessionOpen {
        // Once the target app needs attention, leave the user there, including save sheets.
        self.phase = .idle
        self.hide(cancelClose: false)
        self.onCancelSession?()
        let revealed = await self.revealWindow(target, request)
        if revealed && outcome == .unavailable { outcome = await operation(target, request) }
      }
      if outcome == .closed { self.onClosed?(target, siblings) }
      guard self.session == generation, self.phase.isSessionOpen else { return }
      self.closing = false
      preview?.restore()
      self.panel.content.gridView.setClosing(nil)
      if outcome == .closed {
        self.windows.removeAll { $0.windowID == target.windowID }
        let surviving = Set(self.windows.map(\.windowID))
        self.rerank(following: neighbors.first { surviving.contains($0.windowID) }?.windowID, animateResize: true)
        self.panel.content.showStatus(nil)
      } else {
        // Keep the target even if an intervening snapshot missed it (e.g. a save sheet).
        if !self.windows.contains(where: { $0.windowID == target.windowID }) { self.windows.append(target) }
        self.rerank(following: target.windowID)
        self.panel.content.showStatus(outcome.message)
      }
      self.onCloseFinished?()
    }
  }
}
