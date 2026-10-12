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

// 原样保留 —— 这个测试跟列表还是网格无关，改成网格时不要顺手删掉。
@Test @MainActor func emptyPlaceholderIsHiddenOnlyWhenThereAreRows() {
  let content = PanelContentView()
  // 面板控制器负责 emptyLabel 的显隐；这里只钉住默认状态是「隐藏」——
  // 列表面板出现的路径上，空态由 reloadRows 显式打开。
  #expect(content.emptyLabel.isHidden)
}
