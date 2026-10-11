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
