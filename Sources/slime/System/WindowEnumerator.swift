import AppKit
import ApplicationServices
import CoreGraphics

/// 见过的窗口：能证明它是真窗口（在屏上或 AX 里匹配上过），也留下最后的
/// 标题/最小化状态（离屏时 AX 读不到，靠这里留用）。
struct KnownWindow: Sendable, Equatable, Codable {
  /// 记录时的 app 名：known 表要跨 slime 重启存活（同一次开机内 windowID 稳定），
  /// 而**重启机器**后 windowID 可能被复用 —— 名字对不上的条目按不认识处理。
  var appName: String
  var title: String
  var minimized: Bool
}

/// 纯过滤的输入形状：一个候选窗口的系统信息。
struct WindowCandidate: Sendable {
  let windowID: UInt32
  let pid: pid_t
  let appName: String
  let onscreen: Bool
  /// 这一轮在 AX 里匹配到的信息（标题/最小化），没匹配上就是 nil。
  let matched: KnownWindow?
  /// AX 把它报成「非标准窗口且无标题」（`AXUnknown`）—— Chromium 的
  /// 菜单栏 / 工具栏条就这么报。用户窗口不可能是这样，见 select。
  let helper: Bool
}

/// 一次枚举的产物 + 更新后的「见过」表（调用方跨次持有并传回来）。
struct WindowEnumeration: Sendable {
  var windows: [Window] = []
  var known: [UInt32: KnownWindow] = [:]
}

/// 窗口枚举：`CGWindowList` 定「有哪些窗口」，AX 取标题和最小化状态
/// （spec §5 / §7）。必须在后台线程跑 —— 一次枚举是成串的跨进程同步 IPC，
/// 跑主线程 = 按下快捷键就转圈（红线 4）。
///
/// 过滤规则：
/// - `layer == 0`、alpha > 0、排除桌面元素、排除本进程 —— 基础可见性；
/// - **不按窗口尺寸过滤**（红线 7）：台前调度搁置的窗口，CG 报的是左侧
///   条带里的小方框，按尺寸会把它们全部丢掉；
/// - app 必须是 `activationPolicy == .regular` —— 菜单栏 app 和系统服务
///   不是切换目标；
/// - **frame 与任一显示器范围相交** —— 显示器范围外的窗口不可能是用户
///   可见的窗口（Chromium 的助手条报 @x=-1920）；台前调度条带 / 其他
///   Space 的窗口 frame 都在屏内，不会误伤（红线 7 禁的是按尺寸，这不是）；
/// - 窗口必须**在屏上**、**有 AX 对应物**、或**在 known 表里**。系统会给
///   每个 app 生一批 layer 0、alpha 1 的幽灵窗口（菜单栏条、缓存窗等），
///   它们从不在屏上、从不在 AX 里 —— 永远进不了 known 表（issue #21）；
/// - **助手条否决**：AX 匹配到「子类型 AXUnknown 且无标题」直接丢弃 ——
///   Chromium 把菜单栏 / 工具栏条经 AX 报成窗口，onscreen / matched /
///   known 三条正面证据全命中，只有应用自己声明的「非标准 + 无标题」能
///   否决它（用户实测 Chrome 3 窗口显示 7 行）。
///
/// `known` 表解的是另一个问题（issue #23）：`kAXWindows` 只暴露**当前
/// Space** 的窗口，公开 API 里免空间过滤的只有主窗口/焦点窗口 —— 一个 app
/// 的第二个窗口只要不在屏上就会消失。known 表记住「见过一次的窗口」：
/// 用户访问过的 Space 里的窗口留下记录，之后离屏也仍然进列表（标题留用）。
/// 从没访问过的其他 Space 窗口进不来 —— 公开 API 的天花板到此为止，
/// 同类工具为补这块改用了私有 WindowServer API（spec §3 非目标）。
enum WindowEnumerator {
  /// 枚举一次。`known` 是上一次的「见过」表（跨次持有，见上）。
  static func enumerate(known previous: [UInt32: KnownWindow]) -> WindowEnumeration {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return WindowEnumeration() }

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

    // 显示器范围外的窗口丢弃：不可能是用户可见的窗口（Chromium 的助手条
    // 报 @x=-1920）。台前调度条带 / 其他 Space 的窗口 frame 都在屏内 ——
    // 不会误伤（红线 7 禁的是按尺寸过滤，这不是尺寸）。拿不到显示器信息时
    // 不判（宁多勿错）。
    // NSScreen.frame 是**左下原点**，而 CGWindowList 的 bounds 是**左上原点** ——
    // 必须换算到同一套坐标再判，否则「上方的那块外接屏」的显示范围在 CG 坐标里
    // 是负 y，它上面的窗口全会被误判成屏外（用户实测：外接屏的窗口一个不剩）。
    // 换算：以主屏高度做 y 翻转（CG 全局坐标的原点是主屏的左上角）。
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let displays = NSScreen.screens.map { screen -> CGRect in
      let f = screen.frame
      return CGRect(
        x: f.origin.x, y: primaryHeight - f.origin.y - f.height,
        width: f.width, height: f.height)
    }
    if !displays.isEmpty {
      raw = raw.filter { Self.isOnAnyDisplay($0.bounds, displays: displays) }
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

    return select(
      raw.map { window in
        let match = axInfo[window.windowID]
        return WindowCandidate(
          windowID: window.windowID,
          pid: window.pid,
          appName: window.appName,
          onscreen: window.onscreen,
          matched: match.map {
            KnownWindow(appName: window.appName, title: $0.title, minimized: $0.minimized)
          },
          helper: match.map { AXWindows.isHelper(subrole: $0.subrole, title: $0.title) } ?? false
        )
      },
      known: previous
    )
  }

  /// 纯函数：过滤 + known 表更新（System 层唯一能单测的部分）。
  ///
  /// - 助手否决：AX 判定为助手条（`AXUnknown` + 空标题）直接丢弃，**优先于**
  ///   其它正面证据（onscreen / matched / known）—— 应用自己声明它是非标准
  ///   窗口且无标题，用户窗口不可能是这样（用户实测 Chrome 3 窗口 7 行）。
  ///   也不进 known 表：助手条在下一次枚举就自愈消失。
  /// - 幽灵过滤：不在屏上、AX 里没有、也从没见过 —— 不是用户开的窗。
  /// - known 表：通过过滤的窗口都写回表里 —— 之后离屏也还在（issue #23），
  ///   标题留用（离屏时 AX 读不到）；表里只留这一轮出现的 id（窗口消失即
  ///   自然修剪，防 id 复用）。
  /// - 这一轮亲眼匹配到的信息优先于旧记忆。
  static func select(
    _ candidates: [WindowCandidate], known: [UInt32: KnownWindow]
  ) -> WindowEnumeration {
    var result = WindowEnumeration()
    for candidate in candidates {
      guard !candidate.helper else { continue }

      // known 条目要 app 名对得上才算数（windowID 只在一次开机内稳定）。
      let remembered = known[candidate.windowID].flatMap {
        $0.appName == candidate.appName ? $0 : nil
      }
      // 幽灵过滤：三种证据都没有，就不是用户开的窗。
      guard candidate.onscreen || candidate.matched != nil || remembered != nil else { continue }

      let info =
        candidate.matched
        ?? remembered
        ?? KnownWindow(appName: candidate.appName, title: "", minimized: false)
      result.known[candidate.windowID] = info
      result.windows.append(
        Window(
          pid: candidate.pid,
          windowID: candidate.windowID,
          appName: candidate.appName,
          // 拿不到标题就留空 —— label 退化成 app 名，不编造（红线 6）。
          title: info.title,
          isMinimized: info.minimized
        )
      )
    }
    return result
  }

  /// 纯函数：frame 与任一显示器范围相交即算在屏内（显示器范围注入，可单测）。
  /// 只丢真正在所有显示器之外的窗口 —— 台前调度条带的小方框、其他 Space
  /// 的窗口 frame、全屏窗口都在屏内。
  ///
  /// `displays` 必须是 **CG 坐标**（左上原点），调用方负责换算 —— 见 enumerate()。
  static func isOnAnyDisplay(_ frame: CGRect, displays: [CGRect]) -> Bool {
    displays.contains { $0.intersects(frame) }
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
    /// 读不到就是空串。真窗口是 `AXStandardWindow`；Chromium 的菜单栏 /
    /// 工具栏条报 `AXUnknown`（助手条判定的依据，见 isHelper）。
    let subrole: String
    let minimized: Bool
  }

  /// 助手条判定：应用把窗口声明成 `AXUnknown` 且没有标题。用户窗口不可能是
  /// 这样（真机对照：Chrome / ZCode / VS Code / 企业微信 / line puppy 的真
  /// 窗口全是 `AXStandardWindow`）。读不到 subrole（空串）时不否决 —— 拿不准
  /// 就不丢（未知窗口的代价是列表多一行，误丢的代价是用户切不到窗口）。
  static func isHelper(subrole: String, title: String) -> Bool {
    subrole == kAXUnknownSubrole && title.isEmpty
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
    // 这是公开 API 能给到的最全范围（同类工具为剩下的部分改用私有 API）。
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
        subrole: Self.string(of: element, kAXSubroleAttribute) ?? "",
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
      subrole: Self.string(of: element, kAXSubroleAttribute) ?? "",
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
