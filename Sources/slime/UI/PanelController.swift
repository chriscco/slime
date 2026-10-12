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
  /// 面板里按 ⌘, 开设置 —— AppDelegate 负责把设置窗口叫到前面。
  var onOpenSettings: (() -> Void)?

  private let panel = PanelWindow()
  /// 玻璃参数的来源。只在 show() 里读一次（spec §8）。
  private let settings = Settings()

  /// 最新快照（cache 推过来），rank 的输入。
  private var windows: [Window] = []
  /// 当前渲染的列表（rank 结果）。
  private var rows: [Window] = []
  private var query = ""
  private var selection = 0
  /// 纯状态机的镜像：phase 与 query 与它同步；selection 只用于喂 reduce。
  private var phase: State = .idle

  /// 空态只有一行文字，纯网格宽度（24pt）比它还窄 —— 收一个下限。
  /// 只在空态生效：有结果时宽度必须跟着卡数收窄（spec §2 第 3 条）。
  private static let emptyStateMinWidth: CGFloat = 180

  /// 空态文字在内容坐标系里 y ≈ 64（padding 12 + headerHeight 46 + 6）、
  /// 14pt 字约 17 高 —— 纯网格高度（70）会把文字下缘裁掉（content 层
  /// masksToBounds）。加回 padding 的下边距要 93，下限取 94 留一点余量。
  private static let emptyStateMinHeight: CGFloat = 94

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
      case .openSettings:
        // 显式藏一次：设置窗口 makeKeyAndOrderFront 后面板会 resignKey 自动
        // 藏起来（0.0.2 §8 的既有行为），但那是副作用不是承诺。
        hide()
        onOpenSettings?()
      }
    }
  }

  // MARK: - 显示 / 隐藏

  private func show() {
    // 新会话从空 query / 第 0 行开始（纯状态表：armed + Tab → holding(m, "", 0)）。
    query = ""
    selection = 0
    panel.content.setSearchText("")
    rerank(following: nil)
    resizeAndPosition()
    // 手动布局：上屏前跑一遍，第一帧就是完整列表（spec §7「瞬时」）。
    panel.content.layoutSubtreeIfNeeded()
    // 只在显示时读一次，不做观察者：设置窗口一旦成为 key，面板就 resignKey
    // 藏起来了，「面板开着时改设置」这个场景不存在（spec §8）。
    panel.applyGlassSettings(settings)
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

  /// 按轴算新的选中。纯计算 —— internal 而不是 private：PanelLayoutTests 直接
  /// 验算，免去驱动真面板发按键。
  ///
  /// 纵向按「排」循环：同一列、排号取模 —— 首排 ↑ 绕到末排（GridLayout 的
  /// shouldAnimate 注释也是这个语义），末排没有这一列时收到最后一个格子。
  /// 横向（和只有一排时的纵向）走普通索引循环。结果恒在 `0..<count`，不可能
  /// 为负 —— 负索引的高亮 frame 落在文档视图外被裁掉，整条高亮会消失。
  static func movedSelection(
    from selection: Int, axis: Axis, step: Int, layout: GridLayout
  ) -> Int {
    let count = layout.count
    guard count > 0 else { return 0 }
    let current = min(max(selection, 0), count - 1)

    if axis == .horizontal {
      return ((current + step) % count + count) % count
    }

    let columns = max(1, layout.columns)
    let rows = max(1, layout.rows)
    let row = current / columns
    let column = current % columns
    let targetRow = ((row + step) % rows + rows) % rows
    return min(targetRow * columns + column, count - 1)
  }

  /// ↑↓ 按「排」循环（首排回绕到末排、末排缺列时收缩到最后一个格子），
  /// ←→ 与 Tab 恒为一格 —— 语义全在纯函数 `movedSelection`。
  private func moveSelection(axis: Axis, step: Int) {
    guard !rows.isEmpty else { return }
    selection = Self.movedSelection(from: selection, axis: axis, step: step, layout: gridLayout)
    panel.content.gridView.setSelection(selection, animated: true)
    panel.content.gridView.scrollSelectionToVisible()
  }

  private func append(_ character: Character) {
    query.append(character)
    panel.content.setSearchText(query)
    selection = 0  // 纯状态表：appendQuery 后选中归零
    rerank(following: nil)
  }

  private func backspace() {
    query = String(query.dropLast())
    panel.content.setSearchText(query)
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

    // 首帧尺寸（连拍里「出现后尺寸再跳」的残留，issue #35）：先定面板尺寸、
    // 让窗口 / 玻璃的布局落地，再把文档宽度传导进 gridView —— rows 赋值
    // （rebuild）拿到的 contentWidth 必须是最终值。旧顺序是赋值在前、
    // resizeAndPosition 在后：文档宽度第一帧落在 gridWidth，下一帧才被
    // setContentWidth 改成最终值。
    gridLayout = GridLayout(count: rows.count)
    resizeAndPosition()
    // 玻璃是窗口的 contentView、内容挂在玻璃上：不跑一遍窗口布局，内容的
    // bounds 可能还是旧尺寸（NSGlassEffectView 不保证自动撑满，design.md）。
    panel.layoutIfNeeded()
    content.render(rows: rows)

    content.gridView.setSelection(selection, animated: false)
    content.gridView.scrollSelectionToVisible()
    content.emptyLabel.isHidden = !rows.isEmpty
  }

  private func resizeAndPosition() {
    // 空态（0 张）纯网格是 24 × 70，比空态文字还窄/矮 —— 宽高都收下限；
    // 有结果时尺寸完全跟着卡数走（宽度收窄、高度最多 3 排）。
    let width =
      rows.isEmpty ? max(gridLayout.panelWidth, Self.emptyStateMinWidth) : gridLayout.panelWidth
    let height =
      rows.isEmpty ? max(gridLayout.panelHeight, Self.emptyStateMinHeight) : gridLayout.panelHeight
    panel.setContentSize(NSSize(width: width, height: height))

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
