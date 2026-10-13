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
  /// MRU 排序、含当前窗口的完整列表。面板读 `snapshot`（滤掉当前窗口）。
  private var all: [Window] = []

  /// 当前窗口的 id：列表不含它（spec §7 —— 切到自己没有意义，滤掉之后
  /// index 0 天然是「上一个用过的窗口」）。
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
  private var known: [UInt32: KnownWindow] = [:]

  /// 快照更新后的回调 —— 面板还开着时静默刷新用。
  var onChange: (([Window]) -> Void)?

  /// 面板要渲染的列表：MRU 序，不含当前窗口。
  var snapshot: [Window] { all.filter { $0.windowID != frontWindowID } }

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
      // front-to-back 的第一个就是当前窗口（本进程的窗口不在枚举结果里）。
      let front = result.windows.first?.windowID
      let sorted = Self.sort(result.windows, byMRU: mru)
      let updatedKnown = result.known
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
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

  private func apply(
    _ windows: [Window], frontWindowID: UInt32?, known: [UInt32: KnownWindow], generation: Int
  ) {
    guard generation == self.generation else { return }
    all = windows
    self.frontWindowID = frontWindowID
    self.known = known
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
    // 前台窗口是哪个不知道（没经过我们的激活链路）：先不动 frontWindowID，
    // 下一次枚举校准；最坏是面板第一帧多列/漏列一个窗口，几十毫秒后静默修正。
    all = Self.sort(all, byMRU: mruPids)
    onChange?(snapshot)
  }

  /// MRU 排序：app 按 MRU 名次，没进过 MRU 的 app 按它在窗口列表里第一次出现的
  /// 位置排在后面；app 内保持 CGWindowList 的 front-to-back 顺序。
  ///
  /// `nonisolated static`（不是 private）是为了 `WindowCacheSortTests` 能直接测。
  /// 4 行的改动不值得为它搬进 `Core/`（CLAUDE.md 第六条「加文件之前先问能不能并进
  /// 已有的那个」）—— 这是对「只有 Core 能单测」的一处有意偏离，见
  /// docs/modules/system/decision.md。
  ///
  /// shortcut: 排序聚拢只保证同一 app 的窗口相邻，不做视觉分组（app 之间加标题 /
  ///           间隔）—— 相邻了还是分不清哪几扇窗属于同一个 app 时再做
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
