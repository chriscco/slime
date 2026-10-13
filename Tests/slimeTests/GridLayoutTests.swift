import Testing

@testable import slime

// 网格数学（spec §5.1）。off-by-one 全藏在这一层，而且只能靠肉眼发现 ——
// 这是本任务存在的全部理由。

@Test func zeroThroughFiveWindowsKeepThePanelSize() {
  let full = GridLayout(count: 5)
  #expect(full.columns == 5)
  for count in 0...5 {
    let layout = GridLayout(count: count)
    #expect(layout.panelWidth == full.panelWidth)
    #expect(layout.panelHeight == full.panelHeight)
    #expect(layout.columns == 5)
  }
  #expect(GridLayout(count: 0).contentHeight == 0)
}

@Test func cardAfterAFullRowWrapsToTheSecondRow() {
  let l = GridLayout(count: GridLayout.maxColumns + 1)
  #expect(l.columns == GridLayout.maxColumns)
  #expect(l.rows == 2)
}

@Test func moreThanThreeRowsScrollsInsteadOfGrowing() {
  // Review Focus 1：一个 app 开 20 个窗口 → 多排，但只显示 3 排。
  let l = GridLayout(count: 20)
  #expect(l.columns == GridLayout.maxColumns)
  #expect(l.rows == (20 + GridLayout.maxColumns - 1) / GridLayout.maxColumns)
  #expect(l.visibleRows == 3)
  // 面板高度只看 visibleRows，不随 count 涨。
  #expect(l.panelHeight == GridLayout(count: 3 * GridLayout.maxColumns).panelHeight)
}

@Test func documentViewIsTallerThanThePanelWhenRowsScroll() {
  // 面板高度只看 visibleRows，但文档视图要能滚到第 4 排以后 ——
  // 完整高度含全部 rows，否则第 4 排永远滚不到（spec §12）。
  let l = GridLayout(count: 20)
  #expect(l.rows == (20 + GridLayout.maxColumns - 1) / GridLayout.maxColumns)
  #expect(l.contentHeight > l.panelHeight)
  #expect(
    l.contentHeight
      == Double(l.rows) * l.cardHeight + Double(l.rows - 1) * l.gap)
}

@Test func originsRunInReadingOrderAndWrap() {
  let l = GridLayout(count: 2 * GridLayout.maxColumns)  // 3 列 × 2 排
  let last = GridLayout.maxColumns - 1
  #expect(l.origin(of: 0).x == 0)
  #expect(l.origin(of: 0).y == 0)
  #expect(l.origin(of: last).x == Double(last) * (l.cardWidth + l.gap))
  #expect(l.origin(of: last).y == 0)
  #expect(l.origin(of: last + 1).x == 0)       // 换行回左
  #expect(l.origin(of: last + 1).y == l.cardHeight + l.gap)
}

@Test func onlySameRowMovesSlide() {
  let l = GridLayout(count: 12)
  #expect(l.shouldAnimate(from: 0, to: 1))
  #expect(!l.shouldAnimate(from: GridLayout.maxColumns - 1, to: GridLayout.maxColumns))  // 换行，只跨一排
  #expect(!l.shouldAnimate(from: GridLayout.maxColumns + 1, to: 0))
}

@Test func tailToHeadWrapDoesNotAnimate() {
  let l = GridLayout(count: 20)
  #expect(!l.shouldAnimate(from: 19, to: 0))   // 末排 → 第 0 排
}

@Test func verticalWrapFromTheFirstRowDoesNotAnimate() {
  // spec §6 点名的那个漏洞：↑ 在首排往上走绕到末排。20 张为多排，
  // 2 在第 0 排、17 在末排 —— 跨多排，高亮不能斜穿面板。
  let l = GridLayout(count: 20)
  #expect(!l.shouldAnimate(from: 2, to: 17))
}

@Test func singleRowGridAlwaysAnimates() {
  // 单排表的首尾回绕是纯横向滑动，看着自然，不该跳。
  let l = GridLayout(count: 4)
  #expect(l.shouldAnimate(from: 3, to: 0))
}

@Test func theWidestPanelStillFitsTheSmallestRealisticScreen() {
  // 卡片从 112×92 涨到 160×120 之后，这是唯一可能不成立的约束（spec §13）。
  // 1366×768 是还在跑 macOS 26 的最窄一档屏。
  let l = GridLayout(count: 12)                // 4 列 × 3 排可见 = 最宽最高的一档
  #expect(l.panelWidth <= 1366 - 40)
  #expect(l.panelHeight <= 768 - 120)          // 菜单栏 + Dock 的余量
}

@Test func groupsHaveHeadersAndOnlyOccupiedRowsAreNavigable() {
  let layout = GridLayout(count: 8, groupStarts: [0, 2])
  #expect(layout.rowStarts == [0, 2, 7])
  #expect(layout.origin(of: 0).y == 28)
  #expect(layout.origin(of: 2).x == 0)
  #expect(layout.origin(of: 2).y > layout.origin(of: 0).y + layout.cardHeight)
  #expect(layout.origin(of: 7).x == 0)
  #expect(layout.contentHeight == layout.origin(of: 7).y + layout.cardHeight)
  #expect(layout.movedSelection(from: 1, axis: .vertical, step: 1) == 3)
  #expect(layout.movedSelection(from: 6, axis: .vertical, step: 1) == 7)
  #expect(layout.movedSelection(from: 7, axis: .vertical, step: 1) == 0)
}

@Test func fiveColumnsFitNarrowScreensWithoutShrinkingTextHeight() {
  let layout = GridLayout(count: 5, availableWidth: 800)
  #expect(layout.panelWidth <= 800)
  #expect(layout.columns == 5)
  #expect(layout.cardWidth < 200)
  #expect(layout.cardHeight > layout.cardWidth / 1.6)
}

@Test func groupedHeadersGrowTheViewportBeforeTheScrollLimit() {
  for starts in [[0], [0, 1]] {
    let layout = GridLayout(count: starts.count, groupStarts: starts)
    #expect(layout.gridHeight == layout.contentHeight)
  }
  let manyGroups = GridLayout(count: 8, groupStarts: Array(0..<8))
  #expect(manyGroups.gridHeight == GridLayout(count: 15).gridHeight)
}
