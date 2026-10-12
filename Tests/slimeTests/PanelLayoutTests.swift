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

// 原样保留 —— 这个测试跟列表还是网格无关，改成网格时不要顺手删掉。
@Test @MainActor func emptyPlaceholderIsHiddenOnlyWhenThereAreRows() {
  let content = PanelContentView()
  // 面板控制器负责 emptyLabel 的显隐；这里只钉住默认状态是「隐藏」——
  // 列表面板出现的路径上，空态由 reloadRows 显式打开。
  #expect(content.emptyLabel.isHidden)
}
