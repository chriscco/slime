import ApplicationServices
import CoreGraphics
import Foundation

/// 窗口枚举：`CGWindowList` 定「有哪些窗口」，AX 取标题和最小化状态
/// （spec §5 / §7）。必须在后台线程跑 —— 一次枚举是成串的跨进程同步 IPC，
/// 跑主线程 = 按下快捷键就转圈（红线 4）。
enum WindowEnumerator {
  /// 所有可切换到的窗口，全局 front-to-back 顺序（第一个是当前窗口）。
  ///
  /// 过滤条件：`kCGWindowLayer == 0`（红线 7 —— **不按窗口尺寸过滤**：
  /// 台前调度搁置的窗口，CG 报的是左侧条带里又小又斜的方框，按尺寸会把它们
  /// 全部丢掉）、排除桌面元素、排除本进程、排除不可见的辅助窗口。
  static func enumerate() -> [Window] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    let ownPid = getpid()
    var raw: [(windowID: UInt32, pid: pid_t, appName: String, bounds: CGRect)] = []
    for info in rawList {
      guard
        let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
        let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
        let windowID = info[kCGWindowNumber as String] as? UInt32,
        let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
        let bounds = Self.bounds(info[kCGWindowBounds as String])
      else { continue }
      // 窗口标题不能从 CGWindowList 拿（要屏幕录制权限，是 0.0.1 的非目标）；
      // 这里只拿不需要权限的 owner name。
      let owner = info[kCGWindowOwnerName as String] as? String ?? ""
      raw.append((windowID, pid, owner, bounds))
    }

    // 每个 app 只建一次 AX element；按 frame 把 AX 窗口和 CGWindow 对上。
    var axInfo: [UInt32: AXWindows.Entry] = [:]
    for (pid, group) in Dictionary(grouping: raw, by: { $0.pid }) {
      let entries = AXWindows.read(pid: pid)
      for window in group {
        if let match = AXWindows.match(bounds: window.bounds, title: nil, in: entries) {
          axInfo[window.windowID] = match
        }
      }
    }

    return raw.map { window in
      let ax = axInfo[window.windowID]
      return Window(
        pid: window.pid,
        windowID: window.windowID,
        appName: window.appName,
        // 拿不到标题就留空 —— label 退化成 app 名，不编造（红线 6）。
        title: ax?.title ?? "",
        isMinimized: ax?.minimized ?? false
      )
    }
  }

  private static func bounds(_ value: Any?) -> CGRect? {
    guard let dict = value as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
    else { return nil }
    return rect
  }
}

/// 一个 app 的 AX 窗口快照。WindowEnumerator 和 WindowActivator 共用它来把
/// CGWindow 和 AX element 对上 —— 「怎么算同一个窗口」两处必须一致。
enum AXWindows {
  struct Entry {
    let element: AXUIElement
    let frame: CGRect
    let title: String
    let minimized: Bool
  }

  /// AX 消息超时。红线 6：**没有这一条，一个无响应的 Electron 应用就能让
  /// 整个切换器瘫掉。** 1 秒是 spec 给的量级（AX 正常是 10–50ms）。
  static let timeout: Float = 1

  /// 读一个 app 的全部 AX 窗口。每个 element 都设超时 —— app element 的超时
  /// 不自动继承给子 element。
  static func read(pid: pid_t) -> [Entry] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, Self.timeout)

    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return [] }

    return windows.compactMap { element in
      AXUIElementSetMessagingTimeout(element, Self.timeout)
      guard let frame = Self.frame(of: element) else { return nil }
      return Entry(
        element: element,
        frame: frame,
        title: Self.string(of: element, kAXTitleAttribute) ?? "",
        minimized: Self.bool(of: element, kAXMinimizedAttribute) ?? false
      )
    }
  }

  /// 把 CGWindow 和 AX 窗口对上：先按 frame 近似匹配；对不上（或没有 frame）
  /// 再退到标题。
  ///
  /// 为什么要退到标题：台前调度搁在左侧条带里的窗口，CG 报的是条带方框、
  /// AX 报的可能是真实位置 —— frame 对不上时按标题找是次优但可行的锚。
  /// 标题匹配在同名窗口（同 app 两个「未命名」）上可能选错 —— 代价是
  /// 标题/最小化状态可能张冠李戴，激活仍会落到这个 app。见 decision.md。
  static func match(bounds: CGRect?, title: String?, in entries: [Entry]) -> Entry? {
    if let bounds, let hit = entries.first(where: { Self.approximatelyEqual($0.frame, bounds) }) {
      return hit
    }
    guard let title, !title.isEmpty else { return nil }
    return entries.first { $0.title == title }
  }

  private static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.origin.x - b.origin.x) <= 2
      && abs(a.origin.y - b.origin.y) <= 2
      && abs(a.size.width - b.size.width) <= 2
      && abs(a.size.height - b.size.height) <= 2
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
    guard let origin = Self.point(of: element, kAXPositionAttribute),
          let size = Self.size(of: element, kAXSizeAttribute)
    else { return nil }
    return CGRect(origin: origin, size: size)
  }

  private static func point(of element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = Self.axValue(of: element, attribute) else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
    return point
  }

  private static func size(of element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let value = Self.axValue(of: element, attribute) else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else { return nil }
    return size
  }

  private static func axValue(of element: AXUIElement, _ attribute: String) -> AXValue? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let ref = value, CFGetTypeID(ref) == AXValueGetTypeID()
    else { return nil }
    return unsafeDowncast(ref as AnyObject, to: AXValue.self)
  }

  private static func string(of element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let s = value as? String
    else { return nil }
    return s
  }

  private static func bool(of element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let n = value as? Bool
    else { return nil }
    return n
  }
}
