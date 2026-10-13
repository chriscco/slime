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

  #expect(content.gridView.layout.columns == 5)
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

@Test @MainActor func cardAfterAFullRowWrapsAtTheLeftEdge() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
  let n = GridLayout.maxColumns + 2  // 满排 + 换行后的两张（尺寸是调参值，断言用公式）
  content.gridView.rows = (1...n).map { window("Chrome", "W\($0)", id: UInt32($0)) }
  content.layoutSubtreeIfNeeded()

  #expect(content.gridView.layout.rows == 2)
  let cards = content.gridView.subviews.compactMap { $0 as? CardView }
  #expect(cards.count == n)
  // 换行的那张：前一张还在第一排，它 y 变大（flipped 文档视图 y 向下）、
  // x 回到排首。
  let wrap = GridLayout.maxColumns
  #expect(cards[wrap - 1].frame.minY == cards[0].frame.minY)
  #expect(cards[wrap].frame.minY > cards[wrap - 1].frame.minY)
  #expect(cards[wrap].frame.minX == cards[0].frame.minX)
}

// 键盘移动的集成：GridLayout + 轴语义。真按键的移动全走这个纯函数
// （PanelController.moveSelection 里只有它 + 高亮刷新）。
@Test @MainActor func upFromTheFirstRowWrapsToTheLastRow() {
  // 满排 + 1 个窗口 = 两排：首排 ↑ 应与「同一列的上一排」循环等价 → 末排那一格，
  // 而不是 0 − 列数的普通索引取模（那样恒在首排漂移）。
  let cols = GridLayout.maxColumns
  let twoRows = GridLayout(count: cols + 1)
  #expect(PanelController.movedSelection(from: 0, axis: .vertical, step: -1, layout: twoRows) == cols)
  #expect(PanelController.movedSelection(from: cols, axis: .vertical, step: 1, layout: twoRows) == 0)

  // 满排 ×2 + 1 = 三排：↑ 到末排第一格；→ 只挪一格。
  let threeRows = GridLayout(count: 2 * cols + 1)
  #expect(
    PanelController.movedSelection(from: 0, axis: .vertical, step: -1, layout: threeRows)
      == 2 * cols)
  #expect(PanelController.movedSelection(from: 3, axis: .horizontal, step: 1, layout: threeRows) == 4)

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

// 0.0.5 removes the outline; only a short underline moves.
@Test @MainActor func highlightUsesAnUnderlineInsteadOfAnOutline() throws {
  let grid = CardGridView()
  let highlight = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  #expect(highlight.layer?.borderWidth == 0)
  grid.rows = [window("Chrome", "A", id: 1)]
  grid.setSelection(0, animated: false)
  #expect(highlight.frame.height == 4)
  #expect(highlight.frame.width == 32)
}

@Test @MainActor func highlightColorIsPushedInFromTheOutside() throws {
  // 高亮拿不到 Settings —— 面板 show() 时推一次（不做观察者，同 0.0.2 §8）。
  let grid = CardGridView()
  let highlight = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  grid.highlightColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
  #expect(highlight.layer?.backgroundColor == NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor)
}

// spec §6 / §12：没有缩略图（没权限、抓失败、台前调度搁置）时卡片必须退回
// app 图标，不能是空白。卡片尺寸也不变 —— 混排时不该有两种卡形。
@Test @MainActor func cardFallsBackToTheAppIconWhenThereIsNoThumbnail() throws {
  let chrome = window("Chrome", "GitHub", id: 909)
  let card = CardView(window: chrome)
  card.frame = NSRect(x: 0, y: 0, width: 160, height: 120)
  card.layoutSubtreeIfNeeded()

  let preview = try #require(card.subviews.compactMap { $0 as? WindowPreviewView }.first)
  #expect(WindowThumbnails.image(for: chrome) == nil)
  #expect(preview.image == nil)
  #expect(preview.appIcon === AppIcons.icon(for: chrome))
  #expect(preview.toolTip == localized("Preview unavailable", "无法获取预览"))

}

// 缩略图区在上、标题在下，两者不重叠（spec §5.4：图区 + 间隙 + 标题）。
@Test @MainActor func cardLaysTheThumbnailAboveTheTitle() throws {
  let card = CardView(window: window("Chrome", "GitHub", id: 910))
  let cell = GridLayout(count: 1)
  card.frame = NSRect(x: 0, y: 0, width: cell.cardWidth, height: cell.cardHeight)
  card.layoutSubtreeIfNeeded()

  let thumb = try #require(card.subviews.compactMap { $0 as? WindowPreviewView }.first)
  let label = try #require(card.subviews.compactMap { $0 as? NSTextField }.first)
  // 图区 = 卡片 − 底部标题 − 间隙 − 上下内缩（尺寸是调参值，用关系断言）。
  #expect(thumb.frame.maxY <= label.frame.minY)  // flipped：y 向下
  #expect(thumb.frame.height > label.frame.height * 3)  // 图区远大于标题
  #expect(label.frame.maxY <= card.bounds.maxY - 2)
}

@Test @MainActor func cardContentKeepsAnInsetForRoundedSelection() {
  // 用户实测：高亮描边压在缩略图 / 底部标题上。高亮画在**单元格边界**，
  // 所以卡片内容必须内缩 —— 这条钉住「内容和描边不重叠」。
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
  content.gridView.rows = [window("Chrome", "GitHub", id: 1)]
  content.layoutSubtreeIfNeeded()

  let cards = content.gridView.subviews.compactMap { $0 as? CardView }
  #expect(cards.count == 1)
  let card = try! #require(cards.first)
  for sub in card.subviews {
    let frame = sub.frame
    #expect(
      frame.minX >= 2 && frame.minY >= 2
        && frame.maxX <= card.bounds.width - 2 && frame.maxY <= card.bounds.height - 2,
      "子视图 \(type(of: sub)) 压到了高亮描边所在的边界：\(frame) in \(card.bounds)")
  }
}

@Test @MainActor func groupingKeepsCardsButAddsAppHeaders() {
  let grid = CardGridView()
  let first = Window(pid: 10, windowID: 11, appName: "Safari", title: "A", isMinimized: false)
  let second = Window(pid: 20, windowID: 22, appName: "Notes", title: "B", isMinimized: false)
  grid.rows = [first, second]
  let original = cardSubviews(of: grid)
  grid.groupByApp = true
  #expect(grid.layout.groupStarts == [0, 1])
  #expect(grid.layout.origin(of: 1).x == 0)
  #expect(grid.layout.origin(of: 1).y > grid.layout.origin(of: 0).y)
  #expect(cardSubviews(of: grid)[0] === original[0])
  grid.groupByApp = false
  #expect(grid.layout.groupStarts.isEmpty)
  #expect(grid.layout.origin(of: 1).y == 0)
}

@Test @MainActor func portraitPreviewRoundsTheImageItself() throws {
  let preview = WindowPreviewView(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
  preview.image = NSImage(size: NSSize(width: 60, height: 120), flipped: false) { rect in
    NSColor.red.setFill(); rect.fill(); return true
  }
  let rect = WindowPreviewView.imageRect(size: preview.image!.size, in: preview.bounds)
  #expect(rect == NSRect(x: 60, y: 0, width: 60, height: 120))
  let bitmap = try #require(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
  preview.cacheDisplay(in: preview.bounds, to: bitmap)
  let scale = Double(bitmap.pixelsWide) / 180
  #expect(bitmap.colorAt(x: Int(60 * scale), y: 0)!.alphaComponent < 0.1)
  #expect(bitmap.colorAt(x: Int(90 * scale), y: Int(60 * scale))!.redComponent > 0.9)
}

@Test @MainActor func underlineStretchesThenSettlesBelowTheSelectedCard() throws {
  let grid = CardGridView()
  grid.rows = (1...6).map { window("App", "Window", id: UInt32($0)) }
  grid.setSelection(0, animated: false)
  grid.setSelection(1, animated: true)
  let bar = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  #expect(bar.frame.height == 4)
  #expect(bar.frame.width == 32)
  #expect(bar.frame.midX == grid.card(for: 2)?.frame.midX)
  if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    let motion = try #require(bar.layer?.animation(forKey: "selection") as? CAAnimationGroup)
    let width = try #require(motion.animations?.compactMap { $0 as? CAKeyframeAnimation }
      .first { $0.keyPath == "bounds.size.width" })
    let widths = try #require(width.values as? [CGFloat])
    #expect(widths.first == 32)
    #expect(widths.last == 32)
    #expect(widths[1] > 32)
    grid.setSelection(5, animated: true)
    let flight = try #require(bar.layer?.animation(forKey: "selection") as? CAAnimationGroup)
    let flightWidth = try #require(flight.animations?.compactMap { $0 as? CAKeyframeAnimation }
      .first { $0.keyPath == "bounds.size.width" }?.values as? [CGFloat])
    #expect(flight.duration == 0.24)
    #expect(flightWidth[1] > 32)
    #expect(flightWidth.suffix(12).max()! > 32)
    #expect(flightWidth.max()! <= 52)
    let positions = try #require(flight.animations?.compactMap { $0 as? CAKeyframeAnimation }
      .first { $0.keyPath == "position" }?.values as? [NSValue])
    let end = try #require(positions.last?.pointValue)
    #expect(positions.contains { $0.pointValue.y > end.y })
    #expect(positions.allSatisfy { $0.pointValue.y <= end.y + 6 })
    #expect(flightWidth.first == 32)
    #expect(flightWidth.min() == 4)
    #expect(flightWidth.last == 32)
    grid.setSelection(0, animated: true)
    #expect(bar.layer?.animation(forKey: "selection") is CAAnimationGroup)
  }
  grid.setSelection(1, animated: false)
  #expect(bar.layer?.animation(forKey: "selection") == nil)
}

@Test @MainActor func crtUsesAStablePreviewCanvasAndCleansUpItsLightLayers() async throws {
  let card = CardView(window: window("App", "Window", id: 100))
  card.frame = NSRect(x: 0, y: 0, width: 200, height: 160)
  card.layoutSubtreeIfNeeded()
  let closing = Task { await card.preview.animateClose() }
  for _ in 0..<100 {
    if card.preview.layer?.opacity == 0 { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  let canvas = try #require(card.layer?.sublayers?.last)
  #expect(canvas.frame == card.preview.frame)
  #expect(card.preview.layer?.opacity == 0)
  if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    // Collapse the picture while the beam/afterglow retain their own thickness.
    #expect(canvas.animation(forKey: "crt") == nil)
    #expect(canvas.sublayers?.count == 3)
    #expect(canvas.sublayers?.allSatisfy { $0.animation(forKey: "crt") != nil } == true)
  }
  await closing.value
  #expect(canvas.superlayer == nil)
  card.preview.restore()
  #expect(card.preview.layer?.opacity == 1)
  #expect(card.preview.layer?.superlayer === card.layer)
}

@Test @MainActor func refreshingTheSameSelectionKeepsItsInFlightUnderlineMotion() throws {
  guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
  let grid = CardGridView()
  grid.rows = (1...3).map { window("App", "Window", id: UInt32($0)) }
  grid.setSelection(1, animated: true)
  let bar = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  #expect(bar.layer?.animation(forKey: "selection") != nil)
  // An asynchronous enumeration/layout refresh can arrive during this move.
  grid.setSelection(1, animated: false)
  #expect(bar.layer?.animation(forKey: "selection") != nil)
}

@Test @MainActor func retargetedUnderlineDoesNotAccumulateStretch() throws {
  guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
  let grid = CardGridView()
  grid.rows = (1...3).map { window("App", "Window", id: UInt32($0)) }
  let bar = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  bar.frame.size.width = 52 // Retarget while the previous stretch is still expanded.
  grid.setSelection(1, animated: true)
  let group = try #require(bar.layer?.animation(forKey: "selection") as? CAAnimationGroup)
  let stretch = try #require(group.animations?.compactMap { $0 as? CAKeyframeAnimation }
    .first { $0.keyPath == "bounds.size.width" })
  let widths = try #require(stretch.values as? [CGFloat])
  #expect(widths.first == 52)
  #expect(widths.last == 32)
  #expect(widths.allSatisfy { $0 <= 52 })
}

@Test @MainActor func interruptedFlightKeepsItsVerticalPositionWhenMovingAlongTheNewRow() throws {
  guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
  let grid = CardGridView()
  grid.rows = (1...7).map { window("App", "Window", id: UInt32($0)) }
  grid.setSelection(5, animated: false)
  let bar = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
  bar.frame.origin.y -= 80 // The previous flight has not reached this row yet.
  let start = try #require(bar.layer?.position)
  grid.setSelection(6, animated: true)
  let group = try #require(bar.layer?.animation(forKey: "selection") as? CAAnimationGroup)
  let positions = try #require(group.animations?.compactMap { $0 as? CAKeyframeAnimation }
    .first { $0.keyPath == "position" }?.values as? [NSValue])
  #expect(positions.first?.pointValue == start)
}

@Test @MainActor func crossRowTravelHappensAsADotBeforeTheLineUnfolds() throws {
  guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
  for (from, to) in [(0, 5), (5, 0), (4, 5), (6, 0)] {
    let grid = CardGridView()
    grid.rows = (1...7).map { window("App", "Window", id: UInt32($0)) }
    grid.setSelection(from, animated: false)
    grid.setSelection(to, animated: true)
    let bar = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
    let group = try #require(bar.layer?.animation(forKey: "selection") as? CAAnimationGroup)
    let animations = try #require(group.animations?.compactMap { $0 as? CAKeyframeAnimation })
    let positions = try #require(animations.first { $0.keyPath == "position" }?.values as? [NSValue])
    let widths = try #require(animations.first { $0.keyPath == "bounds.size.width" }?.values as? [CGFloat])
    let start = try #require(positions.first?.pointValue)
    let end = try #require(positions.last?.pointValue)
    let dy = end.y - start.y
    var travellingFrames = 0
    for (point, width) in zip(positions, widths) {
      let progress = (point.pointValue.y - start.y) / dy
      if progress > 0.02 && progress < 0.98 {
        travellingFrames += 1
        #expect(abs(width - bar.frame.height) < 0.01)
      }
    }
    #expect(travellingFrames >= 12)
  }
}
