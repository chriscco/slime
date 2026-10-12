import AppKit

/// 面板控制器：搜索框、卡片网格、高亮、显示/隐藏，以及 lingering 下的键盘
/// （NSEvent → Event → **同一个** reduce，spec §6 两个事件源一个状态机）。
///
/// 展示层的两个账本，纯状态机不知道：
/// - `query`：与搜索框显示文本一致；纯状态机的 `query` 与它同步（两边都只
///   追加/删尾）。打字时纯状态机的 `selection` 归零，这里跟着归零。
/// - `selection`：**循环取模**、刷新后按身份跟随 —— 纯状态机的 `selection`
///   是无界计数（见 docs/modules/trigger/design.md），显示选中以这里为准。
@MainActor
final class PanelController {
  /// 用户确认切换（回车 / 松手）时回调 —— AppDelegate 负责激活 + 更新 MRU。
  var onActivate: ((Window) -> Void)?
  /// showPanel 时回调 —— AppDelegate 触发后台重枚举（spec §7 数据流）。
  var onRefresh: (() -> Void)?

  private let panel = PanelWindow()

  /// 最新快照（cache 推过来），rank 的输入。
  private var windows: [Window] = []
  /// 当前渲染的列表（rank 结果）。
  private var rows: [Window] = []
  private var query = ""
  private var selection = 0
  /// 纯状态机的镜像：phase 与 query 与它同步；selection 只用于喂 reduce。
  private var phase: State = .idle

  /// 空态只有一行文字，纯网格宽度（24pt）比它还窄 —— 收一个下限。
  private static let emptyStateMinWidth: CGFloat = 180

  init() {
    panel.onKey = { [weak self] event in self?.key(event) }
    panel.onResignKey = { [weak self] in self?.panelResignedKey() }
  }

  // MARK: - 外部入口

  /// EventTap 的主线程发布口：状态 + 要执行的 Effect。
  func handle(state: State, effects: [Effect]) {
    phase = state
    execute(effects)
  }

  /// 快照更新（cache.onChange）—— 面板还开着时静默刷新（spec §7）。
  func setWindows(_ windows: [Window]) {
    self.windows = windows
    guard panel.isVisible else { return }
    let previous = rows.indices.contains(selection) ? rows[selection].windowID : nil
    rerank(following: previous)
  }

  // MARK: - 键盘（lingering）

  private func key(_ event: Event) {
    let (next, effects) = reduce(phase, event)
    phase = next
    execute(effects)
  }

  // MARK: - Effect 执行

  private func execute(_ effects: [Effect]) {
    for effect in effects {
      switch effect {
      case .passThrough, .swallow:
        break  // 事件级：吞放由发出方（EventTap / PanelWindow）处理
      case .showPanel:
        show()
      case .hidePanel:
        hide()
      case .moveSelection(let axis, let step):
        moveSelection(axis: axis, step: step)
      case .appendQuery(let character):
        append(character)
      case .deleteQueryChar:
        backspace()
      case .focusSearchField:
        focusSearch()
      case .activate:
        activateSelection()
      case .cancel:
        break  // 不切窗口；hidePanel 已负责藏起来，列表下次打开自然重建
      }
    }
  }

  // MARK: - 显示 / 隐藏

  private func show() {
    // 新会话从空 query / 第 0 行开始（纯状态表：armed + Tab → holding(m, "", 0)）。
    query = ""
    selection = 0
    panel.content.searchLabel.stringValue = ""
    rerank(following: nil)
    resizeAndPosition()
    // 手动布局：上屏前跑一遍，第一帧就是完整列表（spec §7「瞬时」）。
    panel.content.layoutSubtreeIfNeeded()
    panel.makeKeyAndOrderFront(nil)
    // 同时后台重枚举，回来静默更新。
    onRefresh?()
  }

  private func hide() {
    panel.orderOut(nil)
  }

  /// 用户点了别的窗口 / 别的 app 抢走 key：藏着走，别留下没有状态驱动的面板。
  private func panelResignedKey() {
    guard panel.isVisible else { return }
    hide()
    phase = .idle
  }

  // MARK: - 列表

  /// 面板当前布局。rerank 之后重建，`resizeAndPosition` 和 moveSelection 都读它。
  private var gridLayout = GridLayout(count: 0)

  private var columnsPerRow: Int { max(1, gridLayout.columns) }

  /// 网格里 ↑↓ 走一排 = `columnsPerRow` 格（spec §6）。Tab / ←→ 恒为一格。
  private func moveSelection(axis: Axis, step: Int) {
    guard !rows.isEmpty else { return }
    let delta = step * (axis == .vertical ? columnsPerRow : 1)
    // 首尾相接：连续 Tab 循环（spec §2 第 7 条）。
    selection = (selection + delta + rows.count) % rows.count
    panel.content.gridView.setSelection(selection, animated: true)
    panel.content.gridView.scrollSelectionToVisible()
  }

  private func append(_ character: Character) {
    query.append(character)
    panel.content.searchLabel.stringValue = query
    selection = 0  // 纯状态表：appendQuery 后选中归零
    rerank(following: nil)
  }

  private func backspace() {
    query = String(query.dropLast())
    panel.content.searchLabel.stringValue = query
    selection = 0  // 纯状态表：deleteQueryChar 后选中归零
    rerank(following: nil)
  }

  /// 过滤 + 排序；选中修进合法范围（spec §7 的三个边界都在这里收口）。
  ///
  /// - `following`：之前选中的窗口身份 —— 还在就跟随它的新位置，
  ///   消失了回第 0 行。传 nil（打字 / 清空后）则按纯状态表的归零语义收口。
  private func rerank(following id: UInt32?) {
    rows = Search.rank(windows, query: query)
    if let id {
      selection = rows.firstIndex { $0.windowID == id } ?? 0
    } else {
      selection = min(max(selection, 0), max(0, rows.count - 1))
    }
    reloadRows()
  }

  private func reloadRows() {
    let content = panel.content
    content.gridView.rows = rows
    gridLayout = GridLayout(count: rows.count)
    content.gridView.setSelection(selection, animated: false)
    content.gridView.scrollSelectionToVisible()
    content.emptyLabel.isHidden = !rows.isEmpty
    resizeAndPosition()
  }

  private func resizeAndPosition() {
    // 空态的面板宽度不能小于空态文字（纯网格宽度只有 24pt）。
    let width = max(gridLayout.panelWidth, Self.emptyStateMinWidth)
    panel.setContentSize(
      NSSize(width: width, height: gridLayout.panelHeight))

    // 出现在鼠标所在屏幕的中间（多屏时不跑到别的屏去）。
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    else { return }
    let frame = panel.frame
    panel.setFrameOrigin(
      NSPoint(
        x: screen.visibleFrame.midX - frame.width / 2,
        y: screen.visibleFrame.midY - frame.height / 2
      ))
  }

  // MARK: - 动作

  /// ⌘F：把（唯一的）视觉焦点放回搜索框。0.0.1 里键盘只有搜索框一个落点，
  /// 这个 Effect 因此是幂等的 —— 给一个可见回执，让 ⌘F 有可观察的确认。
  private func focusSearch() {
    let box = panel.content.searchBox
    box.alphaValue = 0.45
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      box.animator().alphaValue = 1
    }
  }

  private func activateSelection() {
    // 列表为空（没有别的窗口）回车 / 松手都不做事（spec §7）；hidePanel 仍会藏起来。
    guard rows.indices.contains(selection) else { return }
    onActivate?(rows[selection])
  }
}
