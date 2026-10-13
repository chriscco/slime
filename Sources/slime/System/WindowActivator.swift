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
  case closed, unavailable, failed, stillOpen

  var message: String {
    switch self {
    case .closed: ""
    case .unavailable: localized("Cannot safely identify this window's close button.", "无法安全确定此窗口的关闭按钮。")
    case .failed: localized("Could not close this window. Try again in its app.", "无法关闭此窗口，请在所属应用中重试。")
    case .stillOpen: localized("Window is still open. Switch to its app to check for a save dialog.", "窗口仍然打开，请切到所属应用检查保存对话框。")
    }
  }
}

extension WindowActivator {
  /// A close is destructive: unlike activation, never guess by title alone.
  static func closeMatch(bounds: CGRect, entries: [AXWindows.Entry], siblingBounds: [CGRect]) -> Int? {
    guard siblingBounds.filter({ AXWindows.isSameFrame($0, bounds) }).count == 1 else { return nil }
    let matches = entries.indices.filter { AXWindows.isSameFrame(entries[$0].frame, bounds) }
    return matches.count == 1 ? matches[0] : nil
  }

  static func close(_ window: Window) async -> WindowCloseResult {
    await Task.detached(priority: .userInitiated) {
      guard let initial = windowList() else { return .failed }
      guard let info = initial.first(where: { id($0) == window.windowID }) else { return .closed }
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == window.pid,
        let bounds = bounds(info) else { return .unavailable }
      let siblings = initial.filter {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == window.pid
          && ($0[kCGWindowLayer as String] as? Int) == 0
      }
      let entries = AXWindows.read(pid: window.pid)
      guard let index = closeMatch(bounds: bounds, entries: entries,
        siblingBounds: siblings.compactMap(Self.bounds)) else { return .unavailable }
      let target = entries[index].element
      AXUIElementSetMessagingTimeout(target, AXWindows.timeout)
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(target, kAXCloseButtonAttribute as CFString, &value) == .success,
        let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .unavailable }
      let button = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
      AXUIElementSetMessagingTimeout(button, AXWindows.timeout)
      // Revalidate after AX IPC; a closed/replaced or moved target must not be guessed.
      guard let fresh = windowList() else { return .failed }
      guard let current = fresh.first(where: { id($0) == window.windowID }) else { return .closed }
      guard (current[kCGWindowOwnerPID as String] as? pid_t) == window.pid,
        let currentBounds = Self.bounds(current), AXWindows.isSameFrame(currentBounds, bounds)
      else { return .unavailable }
      let freshSiblings = fresh.filter {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == window.pid
          && ($0[kCGWindowLayer as String] as? Int) == 0
      }.compactMap(Self.bounds)
      guard freshSiblings.filter({ AXWindows.isSameFrame($0, bounds) }).count == 1 else { return .unavailable }
      guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return .failed }
      // Acceptance of AXPress is not proof of closure (unsaved documents may show a sheet).
      for _ in 0..<20 {
        guard let list = windowList() else { return .failed }
        if !list.contains(where: { id($0) == window.windowID }) { return .closed }
        try? await Task.sleep(for: .milliseconds(100))
      }
      return .stillOpen
    }.value
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
