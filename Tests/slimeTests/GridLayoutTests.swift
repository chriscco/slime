import Testing

@testable import slime

// 网格数学（spec §5.1）。off-by-one 全藏在这一层，而且只能靠肉眼发现 ——
// 这是本任务存在的全部理由。

@Test func emptyGridHasNoColumnsOrRows() {
  let l = GridLayout(count: 0)
  #expect(l.columns == 0)
  #expect(l.rows == 0)
  #expect(l.visibleRows == 0)
  // 负间隙的回归：count == 0 时 (columns - 1) 是 -1，少写一个 max(0,…)
  // 面板就会比空态文字还窄。断言用公式（尺寸是调参值，不是行为）。
  #expect(l.panelWidth == 2 * l.padding)
  // 没有卡片时没有网格高度：面板只剩 2×padding + headerHeight。
  #expect(l.panelHeight == 2 * l.padding + l.headerHeight)
  #expect(l.contentHeight == 0)
}

@Test func upToMaxColumnsCardsStayInOneRow() {
  for n in 1...GridLayout.maxColumns {
    let l = GridLayout(count: n)
    #expect(l.columns == n)
    #expect(l.rows == 1)
  }
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

@Test func singleResultShrinksThePanelToOneColumn() {
  // Review Focus 3：搜索缩到 1 张 → 不能留 3 个空槽位。
  let one = GridLayout(count: 1)
  let full = GridLayout(count: GridLayout.maxColumns)
  #expect(one.columns == 1)
  #expect(one.panelWidth == 2 * one.padding + one.cardWidth)
  #expect(
    full.panelWidth
      == 2 * full.padding + Double(GridLayout.maxColumns) * full.cardWidth
        + Double(GridLayout.maxColumns - 1) * full.gap)
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

@Test func sameRowAndAdjacentRowMovesAnimate() {
  let l = GridLayout(count: 12)
  #expect(l.shouldAnimate(from: 0, to: 1))
  #expect(l.shouldAnimate(from: GridLayout.maxColumns - 1, to: GridLayout.maxColumns))  // 换行，只跨一排
  #expect(l.shouldAnimate(from: GridLayout.maxColumns + 1, to: 0))
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
