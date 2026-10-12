import AppKit
import ApplicationServices
import CoreGraphics

/// 窗口枚举：`CGWindowList` 定「有哪些窗口」，AX 取标题和最小化状态
/// （spec §5 / §7）。必须在后台线程跑 —— 一次枚举是成串的跨进程同步 IPC，
/// 跑主线程 = 按下快捷键就转圈（红线 4）。
enum WindowEnumerator {
  /// 所有可切换到的**用户窗口**，全局 front-to-back 顺序（第一个是当前窗口）。
  ///
  /// 过滤规则：
  /// - `layer == 0`、alpha > 0、排除桌面元素、排除本进程 —— 基础可见性；
  /// - **不按窗口尺寸过滤**（红线 7）：台前调度搁置的窗口，CG 报的是左侧
  ///   条带里的小方框，按尺寸会把它们全部丢掉；
  /// - app 必须是 `activationPolicy == .regular` —— 菜单栏 app 和系统服务
  ///   不是切换目标；
  /// - 窗口必须**在屏上**或**有 AX 对应物**。系统会给每个 app 生一批
  ///   layer 0、alpha 1 的幽灵窗口（菜单栏条、缓存窗等），它们既不在屏上、
  ///   也不在 `kAXWindows` 里 —— 不滤掉的话，面板会被同一个 app 的十几行
  ///   空标题刷屏，没有窗口的 app 也会出现（issue #21）。
  ///
  /// 已知限制：`kAXWindows` 只暴露**当前 Space** 的窗口，所以其他 Space 上
  /// 的窗口只有「在屏上」时才进得来 —— 公开 API 就到这（alt-tab 为此改用
  /// 了私有 WindowServer API，spec §3 把那条路列为非目标）。
  static func enumerate() -> [Window] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    let ownPid = getpid()
    var regularApp: [pid_t: Bool] = [:]
    var raw: [(windowID: UInt32, pid: pid_t, appName: String, bounds: CGRect, onscreen: Bool)] = []
    for info in rawList {
      guard
        let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
        let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
        let windowID = info[kCGWindowNumber as String] as? UInt32,
        let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
        let bounds = Self.bounds(info[kCGWindowBounds as String])
      else { continue }

      // app 级过滤（每个 pid 查一次）。
      var isRegular = regularApp[pid]
      if isRegular == nil {
        isRegular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        regularApp[pid] = isRegular
      }
      guard isRegular == true else { continue }

      // 窗口标题不能从 CGWindowList 拿（要屏幕录制权限，是 0.0.1 的非目标）；
      // 这里只拿不需要权限的 owner name 和「是否在屏上」。
      let owner = info[kCGWindowOwnerName as String] as? String ?? ""
      // 幽灵窗口整个键都不存在（不是 false，是没有）。真窗口才有这个键。
      let onscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
      raw.append((windowID, pid, owner, bounds, onscreen))
    }

    // 每个 app 只建一次 AX element；按 frame 把 AX 窗口和 CGWindow 对上。
    //
    // 一个 AX 窗口只认领一个 CGWindow：系统会给真窗口生一份**同 frame 的
    // 孪生幽灵**，不加这一步会多出整行一模一样的重复项（issue #21）。
    // 在屏上的优先 —— 孪生里只有一个是真在显示的。
    var axInfo: [UInt32: AXWindows.Entry] = [:]
    for (pid, group) in Dictionary(grouping: raw, by: { $0.pid }) {
      let entries = AXWindows.read(pid: pid)
      var claimed: [CGRect] = []
      let ordered = group.enumerated()
        .sorted { a, b in
          a.element.onscreen != b.element.onscreen
            ? a.element.onscreen
            : a.offset < b.offset
        }
        .map { $0.element }
      for window in ordered {
        guard
          let match = AXWindows.match(bounds: window.bounds, title: nil, in: entries),
          !claimed.contains(where: { AXWindows.isSameFrame($0, match.frame) })
        else { continue }
        claimed.append(match.frame)
        axInfo[window.windowID] = match
      }
    }

    return raw.compactMap { window -> Window? in
      let ax = axInfo[window.windowID]
      // 幽灵过滤：不在屏上、又没有 AX 对应物的，不是用户开的窗。
      guard window.onscreen || ax != nil else { return nil }
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

    var entries = readWindows(app)
    // 补上主窗口：`kAXWindows` 只给当前 Space 的窗口，而 `kAXMainWindow`
    // 不受 Space 过滤 —— 其他 Space 上每个 app 的前台窗口靠它进列表。
    // 这是公开 API 能给到的最全范围（alt-tab 为剩下的部分改用私有 API）。
    if let main = entry(of: app, kAXMainWindowAttribute as CFString) {
      if !entries.contains(where: { Self.isSameFrame($0.frame, main.frame) }) {
        entries.append(main)
      }
    }
    return entries
  }

  private static func readWindows(_ app: AXUIElement) -> [Entry] {
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

  private static func entry(of app: AXUIElement, _ attribute: CFString) -> Entry? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, attribute, &value) == .success,
      let ref = value, CFGetTypeID(ref) == AXUIElementGetTypeID()
    else { return nil }
    let element = unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(element, Self.timeout)
    guard let frame = Self.frame(of: element) else { return nil }
    return Entry(
      element: element,
      frame: frame,
      title: Self.string(of: element, kAXTitleAttribute) ?? "",
      minimized: Self.bool(of: element, kAXMinimizedAttribute) ?? false
    )
  }

  /// 把 CGWindow 和 AX 窗口对上：先按 frame 近似匹配；对不上（或没有 frame）
  /// 再退到标题。
  ///
  /// 为什么要退到标题：台前调度搁在左侧条带里的窗口，CG 报的是条带方框、
  /// AX 报的可能是真实位置 —— frame 对不上时按标题找是次优但可行的锚。
  /// 标题匹配在同名窗口（同 app 两个「未命名」）上可能选错 —— 代价是
  /// 标题/最小化状态可能张冠李戴，激活仍会落到这个 app。见 decision.md。
  static func match(bounds: CGRect?, title: String?, in entries: [Entry]) -> Entry? {
    if let bounds, let hit = entries.first(where: { Self.isSameFrame($0.frame, bounds) }) {
      return hit
    }
    guard let title, !title.isEmpty else { return nil }
    return entries.first { $0.title == title }
  }

  static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
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
