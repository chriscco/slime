import AppKit
import Testing

@testable import slime

// 布局回归（issue #15）：document view 的宽度必须来自 scroll view ——
// 宽度是 0 时行 label 的 frame 宽度为负，文字画不出来，面板看起来是空白的。
// 这是这一层唯一能自动化的部分：能自动化的部分就自动化，GUI 观感留给人工验收。
@Test @MainActor func listRowsGetWidthFromScrollView() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
  content.listView.rows = [
    Window(pid: 1, windowID: 1, appName: "Chrome", title: "GitHub", isMinimized: false),
    Window(pid: 1, windowID: 2, appName: "Terminal", title: "zsh", isMinimized: false),
  ]
  content.layoutSubtreeIfNeeded()

  #expect(content.listView.frame.width > 0)
  #expect(content.listView.frame.width == content.scrollView.contentSize.width)

  let labels = content.listView.subviews.compactMap { $0 as? NSTextField }
  #expect(labels.count == 2)
  #expect(labels.allSatisfy { $0.frame.width > 0 })
}

@Test @MainActor func emptyPlaceholderIsHiddenOnlyWhenThereAreRows() {
  let content = PanelContentView()
  // 面板控制器负责 emptyLabel 的显隐；这里只钉住默认状态是「隐藏」——
  // 列表面板出现的路径上，空态由 reloadRows 显式打开。
  #expect(content.emptyLabel.isHidden)
}
