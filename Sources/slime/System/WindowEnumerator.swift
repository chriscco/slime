import AppKit
import ApplicationServices
import CoreGraphics

/// 跨 Space 保留标题和最小化状态；只有标准 AX 窗口能为无标题缓存提供长期证据。
struct KnownWindow: Sendable, Equatable, Codable {
  /// 记录时的 app 名：known 表要跨 slime 重启存活（同一次开机内 windowID 稳定），
  /// 而**重启机器**后 windowID 可能被复用 —— 名字对不上的条目按不认识处理。
  var appName: String
  var title: String
  var minimized: Bool
  var axVerified: Bool? = nil
  var observedOnscreen: Bool? = nil
  var confirmed: Bool { axVerified == true || observedOnscreen == true || minimized }
  var closed: Bool? = nil
  // shortcut: retain unseen siblings until AX sees them again; external closes with retained CG surfaces need per-window AX observation.
  var survivedClose: Bool? = nil
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
  var cgTitle: String? = nil
  var axAvailable: Bool = false
  var appHasNoWindows: Bool = false
  var appHasWindows: Bool = false
}

/// 一次枚举的产物 + 更新后的「见过」表（调用方跨次持有并传回来）。
struct WindowEnumeration: Sendable {
  var windows: [Window] = []
  var known: [UInt32: KnownWindow] = [:]
  var targets: [UInt32: NativeWindowTarget] = [:]
}

/// 后台枚举 CG 窗口，用 AX 和可用的 CG 标题排除辅助表面。
/// 不按尺寸过滤：台前调度会把真实窗口缩成条带。AX 的当前 Space 列表
/// 不能单独证明窗口关闭；只有列表为空且 main 明确无值时才清掉该 app。
enum WindowEnumerator {
  /// 枚举一次。`known` 是上一次的「见过」表（跨次持有，见上）。
  static func enumerate(known previous: [UInt32: KnownWindow], request: AXRequest = AXRequest(), targets previousTargets: [UInt32: NativeWindowTarget] = [:]) -> WindowEnumeration {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return WindowEnumeration() }

    let ownPid = getpid()
    var regularApp: [pid_t: Bool] = [:]
    var raw: [(windowID: UInt32, pid: pid_t, appName: String, bounds: CGRect, onscreen: Bool, title: String?)] = []
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

      // nil means screen-recording access is unavailable; empty is an actual unnamed surface.
      let owner = info[kCGWindowOwnerName as String] as? String ?? ""
      // 离屏真窗口和辅助表面都可能没有这个键。
      let onscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
      raw.append((windowID, pid, owner, bounds, onscreen, info[kCGWindowName as String] as? String))
    }

    // 显示器范围外的窗口丢弃：不可能是用户可见的窗口（Chromium 的助手条
    // 报 @x=-1920）。台前调度条带 / 其他 Space 的窗口 frame 都在屏内 ——
    // 不会误伤（红线 7 禁的是按尺寸过滤，这不是尺寸）。拿不到显示器信息时
    // 不判（宁多勿错）。
    // NSScreen.frame 是**左下原点**，而 CGWindowList 的 bounds 是**左上原点** ——
    // 必须换算到同一套坐标再判，否则「上方的那块外接屏」的显示范围在 CG 坐标里
    // 是负 y，它上面的窗口全会被误判成屏外（用户实测：外接屏的窗口一个不剩）。
    // 换算：以主屏高度做 y 翻转（CG 全局坐标的原点是主屏的左上角）。
    let displays = Self.displayBounds()
    if !displays.isEmpty {
      raw = raw.filter { Self.isOnAnyDisplay($0.bounds, displays: displays) }
    }

    // 每个 AX element 最多认领一个 CG 表面；同位置的不同真窗口仍可分别匹配。
    var axInfo: [UInt32: AXWindows.Entry] = [:]
    var snapshots: [pid_t: AXWindows.Snapshot] = [:]
    for (pid, group) in Dictionary(grouping: raw, by: { $0.pid }) {
      guard request.isActive else { return WindowEnumeration() }
      let snapshot = AXWindows.snapshot(pid: pid, request: request, retaining: previousTargets.values.filter { $0.pid == pid })
      snapshots[pid] = snapshot
      let entries = snapshot.entries
      var claimed: Set<Int> = []
      let ordered = group.enumerated()
        .sorted { a, b in
          let aKnown = previousTargets[a.element.windowID]?.pid == pid
          let bKnown = previousTargets[b.element.windowID]?.pid == pid
          if aKnown != bKnown { return aKnown }
          if a.element.onscreen != b.element.onscreen { return a.element.onscreen }
          let aTitled = a.element.title.map { !$0.isEmpty } ?? false
          let bTitled = b.element.title.map { !$0.isEmpty } ?? false
          if aTitled != bTitled { return aTitled }
          return a.offset < b.offset
        }
        .map { $0.element }
      for window in ordered {
        let available = entries.indices.filter { !claimed.contains($0) }
        let identity = previousTargets[window.windowID].flatMap { $0.pid == pid ? $0.element : nil }
        guard let match = AXWindows.match(bounds: window.bounds, title: window.title,
          in: available.map { entries[$0] }, identity: identity),
          let index = available.first(where: { CFEqual(entries[$0].element, match.element) }) else { continue }
        // A unique AX match is insufficient when multiple CG surfaces claim it.
        if identity == nil {
          let frames = group.filter { AXWindows.isSameFrame($0.bounds, match.frame) }
          let titles = group.filter { $0.title == match.title && !match.title.isEmpty }
          guard canClaim(windowID: window.windowID, frameMatches: frames.map(\.windowID),
            titleMatches: titles.map(\.windowID), visibleFrameMatches: frames.filter(\.onscreen).map(\.windowID)) else { continue }
        }
        claimed.insert(index)
        axInfo[window.windowID] = entries[index]
      }
    }

    var result = select(
      raw.map { window in
        let match = axInfo[window.windowID]
        return WindowCandidate(
          windowID: window.windowID,
          pid: window.pid,
          appName: window.appName,
          onscreen: window.onscreen,
          matched: match.map {
            KnownWindow(appName: window.appName, title: $0.title, minimized: $0.minimized,
              axVerified: $0.subrole == kAXStandardWindowSubrole)
          },
          helper: match.map { AXWindows.isHelper(subrole: $0.subrole, title: $0.title) } ?? false,
          cgTitle: window.title,
          axAvailable: snapshots[window.pid]?.available ?? false,
          appHasNoWindows: snapshots[window.pid]?.hasNoWindows ?? false,
          appHasWindows: snapshots[window.pid]?.entries.contains { $0.subrole == kAXStandardWindowSubrole } ?? false
        )
      },
      known: previous
    )
    for window in result.windows {
      if let entry = axInfo[window.windowID] {
        result.targets[window.windowID] = NativeWindowTarget(pid: window.pid, windowID: window.windowID, element: entry.element)
      } else if let target = previousTargets[window.windowID], target.pid == window.pid {
        result.targets[window.windowID] = target
      }
    }
    return result
  }

  /// 当轮证据优先于缓存；被否决的条目不会写回，旧幽灵缓存自动清理。
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
      if remembered?.closed == true, !candidate.onscreen, candidate.matched == nil {
        result.known[candidate.windowID] = remembered
        continue
      }
      // Closing one window can empty the current-Space AX list without closing its siblings.
      guard !candidate.appHasNoWindows || remembered?.survivedClose == true else { continue }
      let titled = candidate.cgTitle.map { !$0.isEmpty } ?? false
      // Onscreen alone admits Chromium toolbar hosts. A readable AX snapshot plus
      // an explicitly empty CG title needs stronger evidence, including for old caches.
      let visible = candidate.onscreen && !(candidate.axAvailable && candidate.cgTitle == "")
      let retained = remembered != nil && (candidate.cgTitle == nil || titled
        || remembered?.axVerified == true || remembered?.minimized == true)
      // A partial AX list must not make lost cache entries permanently unrecoverable.
      let discoverable = titled && candidate.appHasWindows
      guard visible || candidate.matched != nil || retained || discoverable else { continue }

      var info =
        candidate.matched
        ?? remembered
        ?? KnownWindow(appName: candidate.appName, title: "", minimized: false)
      let retainedAXTitle = candidate.matched == nil && remembered?.axVerified == true && remembered?.title.isEmpty == false
      if titled, !retainedAXTitle, candidate.matched?.title.isEmpty != false, let title = candidate.cgTitle {
        info.title = title
      }
      info.observedOnscreen = candidate.onscreen || remembered?.observedOnscreen == true ? true : nil
      info.closed = nil
      info.survivedClose = candidate.matched == nil ? remembered?.survivedClose : nil
      result.known[candidate.windowID] = info
      result.windows.append(
        Window(
          pid: candidate.pid,
          windowID: candidate.windowID,
          appName: candidate.appName,
          // 拿不到标题就留空 —— label 退化成 app 名，不编造（红线 6）。
          title: info.title,
          isMinimized: info.minimized,
          isOnscreen: candidate.onscreen
        )
      )
    }
    var confirmedTitles: [pid_t: Set<String>] = [:]
    for window in result.windows where !window.title.isEmpty {
      if result.known[window.windowID]?.confirmed == true {
        confirmedTitles[window.pid, default: []].insert(window.title)
      }
    }
    // shortcut: unseen same-title windows on other Spaces need one visible visit; revisit when public APIs provide stronger identity.
    result.windows.removeAll { window in
      guard !window.isOnscreen, !window.title.isEmpty,
            result.known[window.windowID]?.confirmed != true,
            confirmedTitles[window.pid]?.contains(window.title) == true else { return false }
      result.known.removeValue(forKey: window.windowID)
      return true
    }
    return result
  }

  static func canClaim(windowID: UInt32, frameMatches: [UInt32], titleMatches: [UInt32], visibleFrameMatches: [UInt32]) -> Bool {
    frameMatches == [windowID] || titleMatches == [windowID] || visibleFrameMatches == [windowID]
  }

  static func displayBounds() -> [CGRect] {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSScreen.screens.map { screen -> CGRect in
      let f = screen.frame
      return CGRect(
        x: f.origin.x, y: primaryHeight - f.origin.y - f.height,
        width: f.width, height: f.height)
    }
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

/// Shared deadline and cancellation for synchronous AX calls. The lock protects
/// cancellation only; callers never hold it while sending IPC or in the event tap.
final class AXRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private let deadline: ContinuousClock.Instant?

  init(seconds: Double? = nil) {
    deadline = seconds.map { ContinuousClock.now.advanced(by: .seconds($0)) }
  }

  func cancel() { lock.withLock { cancelled = true } }
  var isCancelled: Bool { lock.withLock { cancelled } }
  var isActive: Bool {
    !isCancelled && (deadline.map { ContinuousClock.now < $0 } ?? true)
  }

  func pause(milliseconds: Int) async {
    guard isActive else { return }
    let delay = Duration.milliseconds(milliseconds)
    let remaining = deadline.map { ContinuousClock.now.duration(to: $0) } ?? delay
    if remaining > .zero { try? await Task.sleep(for: min(delay, remaining)) }
  }

  func prepare(_ element: AXUIElement) -> Bool {
    guard isActive else { return false }
    let remaining = deadline.map { ContinuousClock.now.duration(to: $0).components }
    let seconds = remaining.map { Double($0.seconds) + Double($0.attoseconds) / 1e18 } ?? 1
    guard seconds > 0 else { return false }
    AXUIElementSetMessagingTimeout(element, Float(min(1, seconds)))
    return true
  }

  func copy(_ element: AXUIElement, _ attribute: CFString, _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    guard prepare(element) else { return .cannotComplete }
    return AXUIElementCopyAttributeValue(element, attribute, value)
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
  struct Snapshot {
    let entries: [Entry]
    let available: Bool
    let hasNoWindows: Bool
  }

  static func read(pid: pid_t, request: AXRequest = AXRequest()) -> [Entry] {
    snapshot(pid: pid, request: request).entries
  }

  static func snapshot(pid: pid_t, request: AXRequest = AXRequest(), retaining: [NativeWindowTarget] = []) -> Snapshot {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    let status = request.copy(app, kAXWindowsAttribute as CFString, &value)
    let windows = status == .success ? value as? [AXUIElement] : nil
    var entries: [Entry] = []
    if let windows {
      for element in windows {
        guard request.isActive else { break }
        if let entry = entry(element, request: request) { entries.append(entry) }
      }
    }
    let complete = windows.map { entries.count == $0.count } ?? false
    // AXWindows can omit other Spaces. Read retained identities directly so stale CG
    // names cannot overwrite a live AX title merely because that list is partial.
    for target in retaining where !entries.contains(where: { CFEqual($0.element, target.element) }) {
      guard request.isActive else { break }
      if let entry = entry(target.element, request: request) { entries.append(entry) }
    }
    var main: CFTypeRef?
    let mainStatus = request.copy(app, kAXMainWindowAttribute as CFString, &main)
    if mainStatus == .success, let main, CFGetTypeID(main) == AXUIElementGetTypeID() {
      let element = unsafeDowncast(main as AnyObject, to: AXUIElement.self)
      if !entries.contains(where: { CFEqual($0.element, element) }),
         let entry = entry(element, request: request) { entries.append(entry) }
    }
    return Snapshot(entries: entries, available: complete && request.isActive,
      hasNoWindows: complete && entries.isEmpty && windows?.isEmpty == true && mainStatus == .noValue)
  }

  private static func entry(_ element: AXUIElement, request: AXRequest) -> Entry? {
    guard let frame = frame(of: element, request: request) else { return nil }
    let title = string(of: element, kAXTitleAttribute, request: request) ?? ""
    let subrole = string(of: element, kAXSubroleAttribute, request: request) ?? ""
    let minimized = bool(of: element, kAXMinimizedAttribute, request: request) ?? false
    guard request.isActive else { return nil }
    return Entry(element: element, frame: frame, title: title, subrole: subrole, minimized: minimized)
  }

  /// Retained native identity wins; otherwise both frame and title matches must be unique.
  static func match(bounds: CGRect?, title: String?, in entries: [Entry], identity: AXUIElement? = nil) -> Entry? {
    if let identity { return entries.first(where: { CFEqual($0.element, identity) }) }
    if let bounds {
      let matches = entries.filter { Self.isSameFrame($0.frame, bounds) }
      if matches.count == 1 { return matches[0] }
      if let title, !title.isEmpty {
        let titled = matches.filter { $0.title == title }
        if titled.count == 1 { return titled[0] }
      }
    }
    guard let title, !title.isEmpty else { return nil }
    let matches = entries.filter { $0.title == title }
    return matches.count == 1 ? matches[0] : nil
  }

  static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.origin.x - b.origin.x) <= 2
      && abs(a.origin.y - b.origin.y) <= 2
      && abs(a.size.width - b.size.width) <= 2
      && abs(a.size.height - b.size.height) <= 2
  }

  private static func frame(of element: AXUIElement, request: AXRequest) -> CGRect? {
    guard let origin = Self.point(of: element, kAXPositionAttribute, request: request),
          let size = Self.size(of: element, kAXSizeAttribute, request: request)
    else { return nil }
    return CGRect(origin: origin, size: size)
  }

  private static func point(of element: AXUIElement, _ attribute: String, request: AXRequest) -> CGPoint? {
    guard let value = Self.axValue(of: element, attribute, request: request) else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
    return point
  }

  private static func size(of element: AXUIElement, _ attribute: String, request: AXRequest) -> CGSize? {
    guard let value = Self.axValue(of: element, attribute, request: request) else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else { return nil }
    return size
  }

  private static func axValue(of element: AXUIElement, _ attribute: String, request: AXRequest) -> AXValue? {
    var value: CFTypeRef?
    guard
      request.copy(element, attribute as CFString, &value) == .success,
      let ref = value, CFGetTypeID(ref) == AXValueGetTypeID()
    else { return nil }
    return unsafeDowncast(ref as AnyObject, to: AXValue.self)
  }

  private static func string(of element: AXUIElement, _ attribute: String, request: AXRequest) -> String? {
    var value: CFTypeRef?
    guard
      request.copy(element, attribute as CFString, &value) == .success,
      let s = value as? String
    else { return nil }
    return s
  }

  private static func bool(of element: AXUIElement, _ attribute: String, request: AXRequest) -> Bool? {
    var value: CFTypeRef?
    guard
      request.copy(element, attribute as CFString, &value) == .success,
      let n = value as? Bool
    else { return nil }
    return n
  }
}

/// AX references stay in System; the immutable wrapper crosses background queues.
struct NativeWindowTarget: @unchecked Sendable {
  let pid: pid_t
  let windowID: UInt32
  let element: AXUIElement
}
