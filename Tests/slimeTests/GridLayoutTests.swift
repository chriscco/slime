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
  // 面板就会比空态文字还窄（12 而不是 24）。
  #expect(l.panelWidth == 24)
}

@Test func upToFiveCardsStayInOneRow() {
  for n in 1...5 {
    let l = GridLayout(count: n)
    #expect(l.columns == n)
    #expect(l.rows == 1)
  }
}

@Test func sixthCardWrapsToTheSecondRow() {
  let l = GridLayout(count: 6)
  #expect(l.columns == 5)
  #expect(l.rows == 2)
}

@Test func moreThanThreeRowsScrollsInsteadOfGrowing() {
  // Review Focus 1：一个 app 开 20 个窗口 → 4 排，但只显示 3 排。
  let l = GridLayout(count: 20)
  #expect(l.columns == 5)
  #expect(l.rows == 4)
  #expect(l.visibleRows == 3)
  // 面板高度只看 visibleRows，不随 count 涨。
  #expect(l.panelHeight == GridLayout(count: 15).panelHeight)
}

@Test func documentViewIsTallerThanThePanelWhenRowsScroll() {
  // 面板高度只看 visibleRows，但文档视图要能滚到第 4 排以后 ——
  // 完整高度含全部 rows，否则第 4 排永远滚不到（spec §12）。
  let l = GridLayout(count: 20)
  #expect(l.rows == 4)
  #expect(l.contentHeight > l.panelHeight)
  #expect(l.contentHeight == 4 * 92 + 3 * 12)
}

@Test func singleResultShrinksThePanelToTwoColumns() {
  // Review Focus 3：搜索缩到 1 张 → 不能留 4 个空槽位。
  let one = GridLayout(count: 1)
  let five = GridLayout(count: 5)
  #expect(one.columns == 1)
  #expect(one.panelWidth == 24 + 112)          // 2*padding + 1*cardWidth
  #expect(five.panelWidth == 24 + 5 * 112 + 4 * 12)
}

@Test func originsRunInReadingOrderAndWrap() {
  let l = GridLayout(count: 12)
  #expect(l.origin(of: 0).x == 0)
  #expect(l.origin(of: 0).y == 0)
  #expect(l.origin(of: 4).x == 4 * 124)        // cardWidth 112 + gap 12
  #expect(l.origin(of: 4).y == 0)
  #expect(l.origin(of: 5).x == 0)              // 换行回左
  #expect(l.origin(of: 5).y == 104)            // cardHeight 92 + gap 12
}

@Test func sameRowAndAdjacentRowMovesAnimate() {
  let l = GridLayout(count: 12)
  #expect(l.shouldAnimate(from: 0, to: 1))
  #expect(l.shouldAnimate(from: 4, to: 5))     // 换行，只跨一排
  #expect(l.shouldAnimate(from: 5, to: 0))
}

@Test func tailToHeadWrapDoesNotAnimate() {
  let l = GridLayout(count: 20)
  #expect(!l.shouldAnimate(from: 19, to: 0))   // 第 3 排 → 第 0 排
}

@Test func verticalWrapFromTheFirstRowDoesNotAnimate() {
  // spec §6 点名的那个漏洞：↑ 在首排往上走绕到末排，|17-2| = 15 ≠ count-1 = 19，
  // 只判首尾回绕会漏掉它，高亮照样斜穿面板。
  let l = GridLayout(count: 20)
  #expect(!l.shouldAnimate(from: 2, to: 17))
}

@Test func singleRowGridAlwaysAnimates() {
  // 单排表的首尾回绕是纯横向滑动，看着自然，不该跳。
  let l = GridLayout(count: 4)
  #expect(l.shouldAnimate(from: 3, to: 0))
}
