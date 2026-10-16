import AppKit
import ApplicationServices
import CoreGraphics

enum WindowActivationResult: Equatable { case exact, application, cancelled }

enum WindowActivator {
  @MainActor private static var pending: Task<WindowActivationResult, Never>?
  @MainActor private static var generation = 0
  @MainActor private static var pendingPIDs: Set<pid_t> = []

  @MainActor static func activate(_ window: Window, target: NativeWindowTarget?, request: AXRequest,
    activateApp: @escaping @MainActor (pid_t) -> Bool = { pid in
      guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
      app.unhide()
      return app.activate(options: [])
    }, frontmostPID: @escaping @MainActor () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
    raise: @escaping @Sendable (NativeWindowTarget, AXRequest) async -> Bool = raise) async -> WindowActivationResult {
    guard request.isActive else { return .cancelled }
    generation += 1
    let generation = generation
    let previous = pending
    pendingPIDs.insert(window.pid)
    let ownedPIDs = pendingPIDs
    var externalFocus = false
    let center = NSWorkspace.shared.notificationCenter
    let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
      MainActor.assumeIsolated {
        if !ownedPIDs.contains(app.processIdentifier) { externalFocus = true; request.cancel() }
      }
    }
    defer { center.removeObserver(observer) }
    // Immediate app fallback never waits behind enumeration or an older AX operation.
    _ = activateApp(window.pid)
    let operation = Task { @MainActor in
      if let previous {
        _ = await previous.value
        guard !request.isCancelled, !externalFocus, generation == Self.generation,
              frontmostPID().map({ ownedPIDs.contains($0) }) == true else { return WindowActivationResult.cancelled }
        // An already-sent AXRaise cannot be revoked; restore only the latest app after it drains.
        _ = activateApp(window.pid)
      }
      guard !request.isCancelled, !externalFocus, generation == Self.generation else { return .cancelled }
      guard request.isActive, let target, target.pid == window.pid,
            target.windowID == window.windowID else { return .application }
      let exact = await raise(target, request)
      guard !request.isCancelled, !externalFocus, generation == Self.generation else { return .cancelled }
      guard frontmostPID() == window.pid else { return .cancelled }
      return exact ? .exact : .application
    }
    pending = operation
    let result = await operation.value
    if generation == Self.generation { pending = nil; pendingPIDs.removeAll() }
    return result
  }

  private static func raise(_ target: NativeWindowTarget, _ request: AXRequest) async -> Bool {
    let exact = await Task.detached(priority: .userInitiated) {
      guard request.prepare(target.element) else { return false }
      var pid: pid_t = 0
      guard AXUIElementGetPid(target.element, &pid) == .success, pid == target.pid else { return false }
      guard request.prepare(target.element) else { return false }
      AXUIElementSetAttributeValue(target.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
      guard request.prepare(target.element) else { return false }
      guard AXUIElementPerformAction(target.element, kAXRaiseAction as CFString) == .success else { return false }
      let app = AXUIElementCreateApplication(target.pid)
      var focused: CFTypeRef?
      return request.copy(app, kAXFocusedWindowAttribute as CFString, &focused) == .success
        && focused.map { CFEqual($0, target.element) } == true
    }.value
    return exact && request.isActive
  }
}


enum WindowCloseResult: Equatable, Sendable {
  case closed, unavailable, failed, stillOpen, confirmationRequired

  var message: String {
    switch self {
    case .closed: ""
    case .unavailable: localized("Cannot safely identify this window's close button.", "无法安全确定此窗口的关闭按钮。")
    case .failed: localized("Could not close this window. Try again in its app.", "无法关闭此窗口，请在所属应用中重试。")
    case .confirmationRequired: localized("Confirm closing in the application.", "请在应用中确认关闭。")
    case .stillOpen: localized("Window is still open. Switch to its app to check for a save dialog.", "窗口仍然打开，请切到所属应用检查保存对话框。")
    }
  }
}

extension WindowActivator {
  struct CloseCandidate {
    let windowID: UInt32
    let bounds: CGRect
    let title: String?
  }

  static func closeMatch(target: CloseCandidate, entries: [AXWindows.Entry],
                         candidates: [CloseCandidate]) -> Int? {
    let sameFrame = candidates.filter { AXWindows.isSameFrame($0.bounds, target.bounds) }
    let matches = entries.indices.filter { AXWindows.isSameFrame(entries[$0].frame, target.bounds) }
    if sameFrame.count == 1, matches.count == 1 { return matches[0] }
    // Stage Manager transforms CG bounds. Require a live, nonempty title unique
    // among both eligible CG surfaces and standard AX windows in this same PID.
    guard let title = target.title, !title.isEmpty,
          candidates.filter({ $0.title == title }).count == 1 else { return nil }
    let titled = entries.indices.filter {
      entries[$0].subrole == kAXStandardWindowSubrole && entries[$0].title == title
    }
    return titled.count == 1 ? titled[0] : nil
  }

  @MainActor static func revealForClosing(_ window: Window, request: AXRequest) async -> Bool {
    guard request.isActive, let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
    app.unhide()
    guard request.isActive else { return false }
    let activated = app.activate(options: [.activateAllWindows])
    for attempt in 0..<8 {
      guard request.isActive else { return false }
      let raised = await Task.detached(priority: .userInitiated) {
        if !activated && attempt == 0 {
          let application = AXUIElementCreateApplication(window.pid)
          guard request.prepare(application) else { return false }
          AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        guard let list = windowList() else { return false }
        let candidates = closeCandidates(list, pid: window.pid)
        guard let target = candidates.first(where: { $0.windowID == window.windowID }) else { return false }
        let entries = AXWindows.read(pid: window.pid, request: request)
        guard let index = closeMatch(target: target, entries: entries, candidates: candidates) else { return false }
        let element = entries[index].element
        guard request.prepare(element) else { return false }
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard request.prepare(element) else { return false }
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
      }.value
      if raised { return true }
      await request.pause(milliseconds: min(250, 50 * (attempt + 1)))
    }
    return false
  }

  static func close(_ window: Window, request: AXRequest = AXRequest(seconds: 3)) async -> WindowCloseResult {
    // Stage Manager changes geometry during activation. Only retry before AXPress.
    for delay in [0, 80, 160] {
      guard request.isActive else { return .stillOpen }
      if delay > 0 { await request.pause(milliseconds: delay) }
      let result = await closeOnce(window, request: request)
      if result != .unavailable { return result }
    }
    return .unavailable
  }

  private static func closeOnce(_ window: Window, request: AXRequest) async -> WindowCloseResult {
    await Task.detached(priority: .userInitiated) {
      guard request.isActive else { return .stillOpen }
      guard let initial = windowList() else { return .failed }
      guard let info = initial.first(where: { id($0) == window.windowID }) else { return .closed }
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == window.pid else { return .unavailable }
      let candidates = closeCandidates(initial, pid: window.pid)
      guard let candidate = candidates.first(where: { $0.windowID == window.windowID }) else { return .unavailable }
      let entries = AXWindows.read(pid: window.pid, request: request)
      guard let index = closeMatch(target: candidate, entries: entries, candidates: candidates) else { return .unavailable }
      let target = entries[index].element
      var value: CFTypeRef?
      guard request.copy(target, kAXCloseButtonAttribute as CFString, &value) == .success,
        let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .unavailable }
      let button = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
      // Re-read both sides after IPC; the window and AX identity must still agree.
      guard let fresh = windowList() else { return .failed }
      guard fresh.contains(where: { id($0) == window.windowID }) else { return .closed }
      let freshCandidates = closeCandidates(fresh, pid: window.pid)
      guard let current = freshCandidates.first(where: { $0.windowID == window.windowID }),
        AXWindows.isSameFrame(current.bounds, candidate.bounds) else { return .unavailable }
      let freshEntries = AXWindows.read(pid: window.pid, request: request)
      guard let freshIndex = closeMatch(target: current, entries: freshEntries, candidates: freshCandidates),
        CFEqual(target, freshEntries[freshIndex].element) else { return .unavailable }
      guard request.prepare(button) else { return .stillOpen }
      guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return .failed }
      // Poll only the identified target. A save sheet is a handoff, never consent.
      for delay in [50, 100, 150, 250, 400, 500, 500, 500] {
        guard request.isActive else { break }
        guard let list = windowList() else { return .failed }
        guard list.contains(where: { id($0) == window.windowID }) else { return .closed }
        var role: CFTypeRef?
        let state = request.copy(target, kAXRoleAttribute as CFString, &role)
        if state == .invalidUIElement { return .closed }
        var sheets: CFTypeRef?
        if request.copy(target, kAXChildrenAttribute as CFString, &sheets) == .success,
           let children = sheets as? [AXUIElement] {
          for child in children {
            guard request.isActive else { break }
            var childRole: CFTypeRef?
            if request.copy(child, kAXRoleAttribute as CFString, &childRole) == .success,
               childRole as? String == kAXSheetRole { return .confirmationRequired }
          }
        }
        await request.pause(milliseconds: delay)
      }
      return .stillOpen
    }.value
  }

  static func closeCandidates(_ list: [[String: Any]], pid: pid_t) -> [CloseCandidate] {
    list.compactMap { info in
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
            (info[kCGWindowLayer as String] as? Int) == 0,
            let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
            let id = id(info), let frame = bounds(info)
      else { return nil }
      return CloseCandidate(windowID: id, bounds: frame, title: info[kCGWindowName as String] as? String)
    }
  }

  private static func windowList() -> [[String: Any]]? {
    CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
  }
  private static func id(_ info: [String: Any]) -> UInt32? { info[kCGWindowNumber as String] as? UInt32 }
  private static func bounds(_ info: [String: Any]) -> CGRect? {
    guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
  }
}
