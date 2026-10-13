import AppKit

/// 快照 + 后台刷新 + app 级 MRU（spec §7）。
///
/// 缓存策略选的是中间态：启动枚举一次；按下时立刻用快照渲染，同时后台重新
/// 枚举并静默更新。取舍见 docs/modules/system/decision.md。
///
/// 主线程持有。快照是不可变数组，主线程读旧的、后台线程造新的、发布时整体
/// 替换 —— 天然无锁，不共享可变状态（红线 8）。
@MainActor
final class WindowCache {
  /// MRU 排序、含当前窗口的完整列表。面板读 `snapshot`（当前窗口排在末尾）。
  private var all: [Window] = []

  /// 当前窗口仍显示，放在末尾，让默认选中仍指向另一个窗口。
  private(set) var frontWindowID: UInt32?

  /// app 级 MRU，最近被激活的 app 在最前。
  /// shortcut: MRU 只到 app 级（NSWorkspace 通知），窗口级要 AXObserver，0.0.2 再说
  private var mruPids: [pid_t] = []

  /// generation 计数（红线 5）：任何「让在途结果过期」的状态变化都 +1，
  /// 结果回来对不上就扔。用户可能已经 Esc 关掉又重开了，旧结果不能覆盖新状态。
  private var generation = 0

  private var observing = false
  private let queue = DispatchQueue(label: "slime.enumerate", qos: .userInitiated)

  /// 「见过一次是真窗口」的表（枚举器产出、跨次传回）—— 其他 Space 的窗口
  /// 靠它留在列表里。见 WindowEnumerator 的文档。
  ///
  /// **持久化**：同一次开机内 windowID 稳定，所以跨 slime 重启存活是有意义的 ——
  /// 不持久化的话，重启后 known 表为空，Electron 类 app（AX 不暴露窗口）的
  /// 离屏窗口全部被过滤掉，列表只剩当前在屏的那几个。
  private var known: [UInt32: KnownWindow] = [:]

  private let defaults: UserDefaults

  /// known 表的落盘键。不用 `Settings`：那是用户设置的封装，这是缓存。
  private static let knownKey = "cache.knownWindows"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.known = Self.loadKnown(from: defaults)
  }

  private static func loadKnown(from defaults: UserDefaults) -> [UInt32: KnownWindow] {
    guard let data = defaults.data(forKey: knownKey),
          let stored = try? JSONDecoder().decode([StoredKnownWindow].self, from: data)
    else { return [:] }
    return Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.entry) })
  }

  private static func saveKnown(_ known: [UInt32: KnownWindow], to defaults: UserDefaults) {
    let stored = known.map { StoredKnownWindow(id: $0.key, entry: $0.value) }
    guard let data = try? JSONEncoder().encode(stored) else { return }
    defaults.set(data, forKey: knownKey)
  }

  /// 快照更新后的回调 —— 面板还开着时静默刷新用。
  var onChange: (([Window]) -> Void)?

  /// 面板显示全部窗口；当前窗口放在末尾，保留快速切换的默认目标。
  var snapshot: [Window] {
    all.filter { $0.windowID != frontWindowID } + all.filter { $0.windowID == frontWindowID }
  }

  /// 这一轮枚举到的所有窗口（含当前窗口）。给缩略图缓存用 —— 它的清理边界
  /// 是「窗口关没关」，不是「面板显不显示」（见 AppDelegate 的 onChange）。
  var allWindows: [Window] { all }

  func start() {
    observeActivations()
    refresh()
  }

  /// 后台重新枚举。结果回来对 generation，对不上就丢（红线 5）。
  func refresh() {
    generation += 1
    let gen = generation
    let mru = mruPids
    let previous = known
    queue.async { [weak self] in
      let result = WindowEnumerator.enumerate(known: previous)
      let sorted = Self.sort(result.windows, byMRU: mru)
      let updatedKnown = result.known
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          let front = Self.frontWindowID(in: result.windows,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
          self?.apply(sorted, frontWindowID: front, known: updatedKnown, generation: gen)
        }
      }
    }
  }

  /// 我们自己切过去之后立刻更新 MRU：下一次打开的面板里，刚切过的排最前；
  /// 刚离开的窗口不再被当成当前窗口，立刻回到列表（不等后台枚举）。
  func noteActivated(_ window: Window) {
    generation += 1  // 在途的枚举结果按旧 MRU 排的序，作废
    mruPids.removeAll { $0 == window.pid }
    mruPids.insert(window.pid, at: 0)
    frontWindowID = window.windowID
    all = Self.sort(all, byMRU: mruPids)
    onChange?(snapshot)
  }

  func noteClosed(_ window: Window, preserving siblings: [Window] = []) {
    generation += 1
    all.removeAll { $0.windowID == window.windowID }
    for sibling in siblings where sibling.pid == window.pid && sibling.windowID != window.windowID {
      if !all.contains(where: { $0.windowID == sibling.windowID }) { all.append(sibling) }
    }
    all = Self.sort(all, byMRU: mruPids)
    var closed = known[window.windowID] ?? KnownWindow(
      appName: window.appName, title: window.title, minimized: window.isMinimized)
    closed.closed = true
    known[window.windowID] = closed
    for sibling in all where sibling.pid == window.pid {
      var info = known[sibling.windowID] ?? KnownWindow(
        appName: sibling.appName, title: sibling.title, minimized: sibling.isMinimized)
      info.survivedClose = true
      known[sibling.windowID] = info
    }
    Self.saveKnown(known, to: defaults)
    onChange?(snapshot)
  }

  func apply(
    _ windows: [Window], frontWindowID: UInt32?, known: [UInt32: KnownWindow], generation: Int
  ) {
    guard generation == self.generation else { return }
    all = windows
    self.frontWindowID = frontWindowID
    self.known = known
    Self.saveKnown(known, to: defaults)
    onChange?(snapshot)
  }

  private func observeActivations() {
    guard !observing else { return }
    observing = true
    // 观察者活到进程退出，token 不需要留。
    _ = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.processIdentifier != getpid()
      else { return }
      // queue: .main 保证这里在主线程；assumeIsolated 让它能碰 @MainActor 状态。
      MainActor.assumeIsolated { self?.noteFrontApp(app.processIdentifier) }
    }
  }

  /// 别的途径（点窗口、系统原生 ⌘Tab……）换前台 app 时也要记进 MRU。
  private func noteFrontApp(_ pid: pid_t) {
    mruPids.removeAll { $0 == pid }
    mruPids.insert(pid, at: 0)
    // Drop another app's exclusion immediately; preserve an explicit noteActivated target.
    if !all.contains(where: { $0.windowID == frontWindowID && $0.pid == pid }) {
      frontWindowID = Self.frontWindowID(in: all, frontmostPID: pid)
    }
    all = Self.sort(all, byMRU: mruPids)
    onChange?(snapshot)
  }

  nonisolated static func frontWindowID(in windows: [Window], frontmostPID: pid_t?) -> UInt32? {
    windows.first { $0.isOnscreen && $0.pid == frontmostPID }?.windowID
  }

  /// MRU 排序：app 按 MRU 名次，没进过 MRU 的 app 按它在窗口列表里第一次出现的
  /// 位置排在后面；app 内保持 CGWindowList 的 front-to-back 顺序。
  ///
  /// `nonisolated static`（不是 private）是为了 `WindowCacheSortTests` 能直接测。
  /// 4 行的改动不值得为它搬进 `Core/`（CLAUDE.md 第六条「加文件之前先问能不能并进
  /// 已有的那个」）—— 这是对「只有 Core 能单测」的一处有意偏离，见
  /// docs/modules/system/decision.md。
  ///
  nonisolated static func sort(_ windows: [Window], byMRU mru: [pid_t]) -> [Window] {
    var rank: [pid_t: Int] = [:]
    for (index, pid) in mru.enumerated() { rank[pid] = index }
    // 没名次的 app 也得拿到**不重复**的名次：全给 Int.max 就名次并列，并列退回
    // 窗口列表的 z 序 → 同一个 app 的窗口在列表里交错（冷启动必然如此，
    // mruPids 是空的）。按首现位置依次编号。
    var next = mru.count
    for window in windows where rank[window.pid] == nil {
      rank[window.pid] = next
      next += 1
    }
    // `sorted` 不保证稳定：名次相同的窗口（同一个 app 内）靠原下标定序。
    return windows.enumerated()
      .sorted { a, b in
        let ra = rank[a.element.pid] ?? Int.max
        let rb = rank[b.element.pid] ?? Int.max
        return ra != rb ? ra < rb : a.offset < b.offset
      }
      .map { $0.element }
  }
}

/// known 表落盘用的形状（UserDefaults 的 JSON 里字典键得是字符串）。
struct StoredKnownWindow: Codable {
  let id: UInt32
  let entry: KnownWindow
}
