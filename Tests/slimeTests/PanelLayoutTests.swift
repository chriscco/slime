import AppKit
import Testing

@testable import slime

// 布局回归。0.0.1 的同类测试（issue #15）抓的是「document view 宽度为 0 →
// 行的 frame 宽度为负 → 面板看起来是空白的」。网格版换成卡片，
// 但那条契约不变：document view 的宽度必须来自 scroll view。
// 能自动化的部分就自动化，GUI 观感留给人工验收。

private func window(_ app: String, _ title: String, id: UInt32) -> Window {
  Window(pid: 1, windowID: id, appName: app, title: title, isMinimized: false)
}

@Test @MainActor func gridCardsAreLaidOutInReadingOrder() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
  content.gridView.rows = [
    window("Chrome", "GitHub", id: 1),
    window("Chrome", "Claude", id: 2),
    window("iTerm2", "slime", id: 3),
  ]
  content.layoutSubtreeIfNeeded()

  #expect(content.gridView.layout.columns == 3)
  #expect(content.gridView.layout.rows == 1)

  let cards = content.gridView.subviews.compactMap { $0 as? CardView }
  #expect(cards.count == 3)
  // 阅读顺序：x 递增，y 相同。
  #expect(cards[0].frame.minX < cards[1].frame.minX)
  #expect(cards[1].frame.minX < cards[2].frame.minX)
  #expect(cards[0].frame.minY == cards[1].frame.minY)
}

@Test @MainActor func gridColumnsGetWidthFromScrollView() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
  content.gridView.rows = [window("Chrome", "GitHub", id: 1)]
  content.layoutSubtreeIfNeeded()

  #expect(content.gridView.frame.width > 0)
  #expect(content.gridView.frame.width == content.scrollView.contentSize.width)
}

// 首帧尺寸（连拍里「出现后尺寸再跳」的残留，issue #35）：文档宽度必须在
// rows 赋值之前定稿。先模拟 resizeAndPosition 改了面板尺寸，再走生产顺序
// render —— 赋值完宽度即最终值，之后两遍布局都不再二次变化。
@Test @MainActor func documentWidthIsSettledBeforeRowsAreRendered() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 400, height: 320)
  content.layoutSubtreeIfNeeded()  // 旧的（小面板）布局先落地

  content.frame = NSRect(x: 0, y: 0, width: 632, height: 320)  // resizeAndPosition
  content.render(rows: (1...6).map { window("Chrome", "W\($0)", id: UInt32($0)) })

  // 赋值后即为最终宽度：与 scroll view 的 contentSize 一致，且两遍布局后不变。
  let settled = content.gridView.frame.width
  #expect(settled == content.scrollView.contentSize.width)
  content.layoutSubtreeIfNeeded()
  #expect(content.gridView.frame.width == settled)
  content.layoutSubtreeIfNeeded()
  #expect(content.gridView.frame.width == settled)
  #expect(content.gridView.frame.width == content.scrollView.contentSize.width)
}

@Test @MainActor func sixthCardWrapsToTheSecondRowAtTheLeftEdge() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
  content.gridView.rows = (1...6).map { window("Chrome", "W\($0)", id: UInt32($0)) }
  content.layoutSubtreeIfNeeded()

  #expect(content.gridView.layout.rows == 2)
  let cards = content.gridView.subviews.compactMap { $0 as? CardView }
  #expect(cards.count == 6)
  // 第 6 张换行：第 5 张还在第一排，第 6 张 y 变大（flipped 文档视图 y 向下）、
  // x 回到排首。
  #expect(cards[4].frame.minY == cards[0].frame.minY)
  #expect(cards[5].frame.minY > cards[4].frame.minY)
  #expect(cards[5].frame.minX == cards[0].frame.minX)
}

// 键盘移动的集成：GridLayout + 轴语义。真按键的移动全走这个纯函数
// （PanelController.moveSelection 里只有它 + 高亮刷新）。
@Test @MainActor func upFromTheFirstRowWrapsToTheLastRow() {
  // 6 个窗口 = 两排：首排 ↑ 应与「同一列的上一排」循环等价 → 末排（count − 1），
  // 而不是 0 − 5 的普通索引取模（那样恒在首排漂移）。
  let six = GridLayout(count: 6)
  #expect(PanelController.movedSelection(from: 0, axis: .vertical, step: -1, layout: six) == 5)
  #expect(PanelController.movedSelection(from: 5, axis: .vertical, step: 1, layout: six) == 0)

  // 11 个窗口 = 三排：↑ 到末排第一格；⇧Tab 只退一格。
  let eleven = GridLayout(count: 11)
  #expect(PanelController.movedSelection(from: 0, axis: .vertical, step: -1, layout: eleven) == 10)
  #expect(PanelController.movedSelection(from: 3, axis: .horizontal, step: 1, layout: eleven) == 4)

  // 任何 (count, selection, 轴, 方向) 组合都落在 0..<count —— 不允许负索引
  // （负索引的高亮 frame 落在文档视图外，被裁掉 = 高亮整条消失）。
  for count in 1...25 {
    let layout = GridLayout(count: count)
    for selection in 0..<count {
      for (axis, step) in [(Axis.vertical, -1), (.vertical, 1), (.horizontal, -1), (.horizontal, 1)] {
        let moved = PanelController.movedSelection(
          from: selection, axis: axis, step: step, layout: layout)
        #expect(moved >= 0 && moved < count, "count=\(count) selection=\(selection)")
      }
    }
  }
}

// 搜索行：空查询显示占位提示（次要色、不抢视觉），有查询显示查询文本（主色）。
// 无框 pill / 放大镜的观感走人工验收，这里只钉住文本语义。
@Test @MainActor func searchRowShowsPlaceholderOnlyWhenTheQueryIsEmpty() {
  let content = PanelContentView()
  #expect(content.searchLabel.stringValue == PanelContentView.searchPlaceholder)
  #expect(content.searchLabel.textColor == .secondaryLabelColor)

  content.setSearchText("chr")
  #expect(content.searchLabel.stringValue == "chr")
  #expect(content.searchLabel.textColor == .labelColor)
}

// issue #35：刷新时按身份复用卡片。唤出面板「图标闪一下」的根因就是
// rows 每次赋值都全量重建（所有 CardView 拆掉重造）。
@Test @MainActor func sameWindowIDsKeepTheSameCardViews() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
  content.gridView.rows = [
    window("Chrome", "GitHub", id: 1),
    window("iTerm2", "slime", id: 2),
  ]
  let first = cardSubviews(of: content.gridView)
  #expect(first.count == 2)

  // 同 ID 序列（只有标题变了）再赋值：不重建，只就地更新内容。
  content.gridView.rows = [
    window("Chrome", "GitHub — slime PR", id: 1),
    window("iTerm2", "slime", id: 2),
  ]
  let second = cardSubviews(of: content.gridView)
  #expect(second.count == 2)
  #expect(second[0] === first[0])
  #expect(second[1] === first[1])
  #expect(label(of: second[0]) == "GitHub — slime PR")
}

// 行集变了（顺序变化 + 消失 + 新增）：存活的 CardView 复用到新位置，
// 只对新增/消失的做增删 —— 刷新不再是「全部拆掉重造」。
@Test @MainActor func reorderedRowsReuseSurvivingCards() throws {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
  content.gridView.rows = [
    window("Chrome", "A", id: 1),
    window("iTerm2", "B", id: 2),
    window("Safari", "C", id: 3),
  ]
  let before = cardSubviews(of: content.gridView)

  content.gridView.rows = [
    window("Safari", "C", id: 3),
    window("Chrome", "A2", id: 1),
    window("Finder", "D", id: 4),
  ]
  let after = cardSubviews(of: content.gridView)
  #expect(after.count == 3)
  // C 和 A 的实例被复用，不是全部重造。
  #expect(after.contains { $0 === before[2] })
  #expect(after.contains { $0 === before[0] })
  // B 已经离场。
  #expect(before[1].superview == nil)
  // 顺序与数据一致：C 在第 0 列、A 第二、新造的 D 第三（frame 按网格索引排）。
  let newCard = try #require(after.first { card in before.allSatisfy { $0 !== card } })
  #expect(before[2].frame.minX == 0)
  #expect(before[2].frame.minX < before[0].frame.minX)
  #expect(before[0].frame.minX < newCard.frame.minX)
  // 复用的实例就地更新了内容。
  #expect(label(of: before[0]) == "A2")
}

private func cardSubviews(of grid: CardGridView) -> [CardView] {
  grid.subviews.compactMap { $0 as? CardView }
}

private func label(of card: CardView) -> String? {
  card.subviews.compactMap { $0 as? NSTextField }.first?.stringValue
}

// 出场动画（连拍观察到的真正根因，issue #35）：NSWindow 默认的 animationBehavior
// 会在 makeKeyAndOrderFront 后把整块面板从 ~98% 缩放到位 —— 内容跟着一起缩放，
// 用户看到的就是「图标闪一下」，每次召出都会发生。必须关掉。
@Test @MainActor func panelDoesNotAnimateOnAppearance() {
  #expect(PanelWindow().animationBehavior == .none)
}

// 原样保留 —— 这个测试跟列表还是网格无关，改成网格时不要顺手删掉。
@Test @MainActor func emptyPlaceholderIsHiddenOnlyWhenThereAreRows() {
  let content = PanelContentView()
  // 面板控制器负责 emptyLabel 的显隐；这里只钉住默认状态是「隐藏」——
  // 列表面板出现的路径上，空态由 reloadRows 显式打开。
  #expect(content.emptyLabel.isHidden)
}

// spec §8：线条加粗到 2.5。2.5 是提案值，但「不能悄悄回到 2」值得钉住。
@Test @MainActor func highlightOutlineIsThickerThanTheOldTwoPoints() throws {
  let grid = CardGridView()
  let highlight = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  #expect(highlight.layer?.borderWidth == 2.5)
}

@Test @MainActor func highlightColorIsPushedInFromTheOutside() throws {
  // 高亮拿不到 Settings —— 面板 show() 时推一次（不做观察者，同 0.0.2 §8）。
  let grid = CardGridView()
  let highlight = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  grid.highlightColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
  #expect(highlight.layer?.borderColor == NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor)
}
