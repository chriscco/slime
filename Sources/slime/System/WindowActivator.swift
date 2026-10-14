import AppKit
import ApplicationServices
import CoreGraphics

/// 回车 / 松手之后的动作（spec §7）：取消最小化 → `kAXRaiseAction` → activate。
enum WindowActivator {
  /// AX 部分放后台（跨进程 IPC，不占主线程），激活 app 回主线程。
  static func activate(_ window: Window) {
    DispatchQueue.global(qos: .userInitiated).async {
      Self.raise(window)
      DispatchQueue.main.async {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        // ⌘H 隐藏的 app 不 unhide 的话 activate 不会露出来。
        app.unhide()
        // activateAllWindows：只 activate 的话窗口顺序由系统挑；目标窗口
        // 上一段已经 raise 过，整组带上来时它保持在最前。
        app.activate(options: [.activateAllWindows])
      }
    }
  }

  /// 取消最小化 + raise。窗口找不到时的降级：不 raise，只 activate app
  /// —— 比什么都不做强，也不会切错（raise 错窗口才是切错）。
  private static func raise(_ window: Window) {
    let app = AXUIElementCreateApplication(window.pid)
    AXUIElementSetMessagingTimeout(app, AXWindows.timeout)

    let entries = AXWindows.read(pid: window.pid)
    guard let entry = AXWindows.match(
      bounds: Self.cgBounds(of: window.windowID),
      title: window.title.isEmpty ? nil : window.title,
      in: entries
    ) else { return }

    AXUIElementSetMessagingTimeout(entry.element, AXWindows.timeout)
    // 最小化的窗口 raise 不到前台，必须先取消最小化。
    // 对没最小化的窗口是幂等的 no-op。
    AXUIElementSetAttributeValue(
      entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
  }

  /// 指定 windowID 的 CGWindow 现在的 frame —— 台前调度里它可能和上次
  /// 枚举时不一样，所以现查，不依赖快照。
  private static func cgBounds(of windowID: UInt32) -> CGRect? {
    let options: CGWindowListOption = [.optionAll, .optionIncludingWindow]
    guard
      let list = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
      let info = list.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == windowID }),
      let dict = info[kCGWindowBounds as String] as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
    else { return nil }
    return rect
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
