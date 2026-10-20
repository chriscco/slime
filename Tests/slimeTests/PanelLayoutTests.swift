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

// Both placeholder and query use readable semantic text in either appearance.
@Test @MainActor func searchRowShowsPlaceholderOnlyWhenTheQueryIsEmpty() {
  let content = PanelContentView()
  #expect(content.searchLabel.stringValue == PanelContentView.searchPlaceholder)
  #expect(content.searchLabel.textColor == .labelColor)

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

@MainActor private func cardSubviews(of grid: CardGridView) -> [CardView] {
  grid.subviews.compactMap { $0 as? CardView }
}

@MainActor private func label(of card: CardView) -> String? {
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
    #expect(bar.layer?.animation(forKey: "selection") == nil)
    #expect(bar.frame.midX == grid.card(for: 6)?.frame.midX)
    grid.setSelection(0, animated: true)
    #expect(bar.layer?.animation(forKey: "selection") == nil)
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

@Test @MainActor func crossRowSelectionPlacesTheUnderlineImmediately() throws {
  for (from, to) in [(0, 5), (5, 0), (4, 5), (6, 0)] {
    let grid = CardGridView()
    grid.rows = (1...7).map { window("App", "Window", id: UInt32($0)) }
    grid.setSelection(from, animated: false)
    grid.setSelection(to, animated: true)
    let bar = try #require(grid.subviews.compactMap { $0 as? HighlightView }.first)
    let target = try #require(grid.card(for: UInt32(to + 1)))
    #expect(bar.frame == NSRect(x: target.frame.midX - 16, y: target.frame.maxY - 7, width: 32, height: 4))
    #expect(bar.layer?.animationKeys()?.isEmpty != false)
  }
}

extension PanelAndThumbnailTests {
@Test @MainActor func searchFocusShowsCaretAndTypingMovesIt() {
  _ = NSApplication.shared
  let controller = PanelController()
  controller.handle(state: .lingering(query: "", selection: 0), effects: [])
  controller.setWindows([])
  let content = controller.panel.content
  controller.handle(state: .lingering(query: "", selection: 0), effects: [.focusSearchField])
  #expect(content.searchFocused)
  #expect(content.searchBox.layer?.borderWidth == 2)
  #expect(controller.panel.firstResponder === content.searchEditor)
  content.searchEditor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(content.searchEditor.selectedRange().location == 3)
  controller.dismiss()
  #expect(!content.searchFocused)
}
}

@Test @MainActor func repeatingSearchFocusKeepsTheNativeSelection() {
  let content = PanelContentView()
  content.setSearchText("hello")
  content.setSearchFocused(true)
  content.searchEditor.setSelectedRange(NSRange(location: 1, length: 2))
  content.setSearchFocused(true)
  #expect(content.searchEditor.selectedRange() == NSRange(location: 1, length: 2))
}

@Test @MainActor func typingThePlaceholderTextIsStillAQuery() {
  let content = PanelContentView()
  let placeholder = content.searchLabel.stringValue
  content.setSearchText(placeholder)
  #expect(content.searchBox.accessibilityValue() as? String == placeholder)
  #expect(content.searchLabel.textColor == .labelColor)
}

@Test @MainActor func savedWhiteBackgroundChangesThePanelAppearance() throws {
  _ = NSApplication.shared
  let suite = "slime.theme.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set("white", forKey: "panel.background")
  let panel = PanelWindow()
  panel.applyGlassSettings(Settings(defaults: defaults))
  #expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
  #expect(panel.content.layer?.backgroundColor == NSColor.white.withAlphaComponent(Settings.supportsGlass ? 0.87 : 1).cgColor)
}

@Test(arguments: [320.0, 600.0, 1088.0]) @MainActor
func searchHeaderShowsShortcutUntilFocusOrStatusTakesItsPlace(width: Double) throws {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: width, height: 300)
  content.layoutSubtreeIfNeeded()
  let hint = try #require(content.searchBox.subviews.compactMap { $0 as? NSTextField }
    .first { $0.stringValue == "⌘F" })
  #expect(!hint.isHidden)
  #expect(content.searchIcon.superview === content)
  #expect(content.searchIcon.frame.width == 32)
  #expect(content.searchIcon.frame.maxX + 10 == content.searchBox.frame.minX)
  content.setSearchFocused(true)
  #expect(hint.isHidden)
  content.setSearchFocused(false)
  #expect(!hint.isHidden)
  content.showStatus("Close failed")
  content.layoutSubtreeIfNeeded()
  #expect(hint.isHidden)
  content.showStatus(nil)
  content.layoutSubtreeIfNeeded()
  #expect(!hint.isHidden)
  content.setSearchText(String(repeating: "wide query ", count: 30))
  content.layoutSubtreeIfNeeded()
  let clip = try #require(content.searchEditor.enclosingScrollView)
  #expect(clip.frame.maxX < hint.frame.minX)
  #expect(content.searchEditor.isHorizontallyResizable)
  #expect(content.searchEditor.selectedRange().location == (content.searchEditor.string as NSString).length)
}

extension PanelAndThumbnailTests {
@Test @MainActor func systemAppearanceRefreshKeepsTheQueryFocusAndSelection() throws {
  _ = NSApplication.shared
  let suite = "slime.live-theme.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  settings.panelBackground = .system
  let controller = PanelController(settings: settings)
  controller.handle(state: .lingering(query: "", selection: 0), effects: [])
  controller.setWindows([window("App", "Alpha", id: 301), window("App", "Beta", id: 302)])
  controller.handle(state: .lingering(query: "a", selection: 0), effects: [.setQuery("a"), .focusSearchField])
  controller.refreshAppearance()
  #expect(controller.panel.appearance == nil)
  let content = controller.panel.content
  let selection = controller.selection
  let originalAppearance = NSApp.appearance
  defer { NSApp.appearance = originalAppearance }
  NSApp.appearance = NSAppearance(named: .aqua)
  content.layoutSubtreeIfNeeded()
  #expect(controller.panel.content.layer?.backgroundColor == NSColor.white.withAlphaComponent(Settings.supportsGlass ? 0.87 : 1).cgColor)
  #expect(content.searchFocused)
  #expect(content.searchLabel.stringValue == "a")
  #expect(controller.selection == selection)
  NSApp.appearance = NSAppearance(named: .darkAqua)
  content.layoutSubtreeIfNeeded()
  #expect(controller.panel.content.layer?.backgroundColor == NSColor.black.withAlphaComponent(Settings.supportsGlass ? 0.87 : 1).cgColor)
  settings.panelBackground = .white
  controller.refreshAppearance()
  #expect(controller.panel.appearance?.name == .aqua)
  #expect(content.searchFocused)
  #expect(content.searchLabel.stringValue == "a")
  controller.dismiss()
}
}

@Test @MainActor func searchHeaderAlignsRoundedLogoAndUsesThemeAwareTextWithoutHintFill() throws {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 1088, height: 300)
  content.render(rows: (1...5).map { window("App", "Window", id: UInt32($0)) })
  let first = try #require(content.gridView.card(for: 1))
  let last = try #require(content.gridView.card(for: 5))
  let firstPreview = content.convert(first.preview.bounds, from: first.preview)
  let lastPreview = content.convert(last.preview.bounds, from: last.preview)
  #expect(content.searchIcon.frame.minX == firstPreview.minX)
  #expect(content.searchBox.frame.maxX == lastPreview.maxX)
  #expect(content.searchIcon.frame.minY == content.searchBox.frame.minY)
  #expect(content.searchIcon.frame.maxY == content.searchBox.frame.maxY)
  #expect(content.searchIcon.layer?.cornerRadius == 10)
  #expect(content.searchIcon.layer?.masksToBounds == true)
  #expect(content.shortcutHint.layer?.backgroundColor == nil
    || content.shortcutHint.layer?.backgroundColor?.alpha == 0)
  for name in [NSAppearance.Name.darkAqua, .aqua] {
    content.appearance = NSAppearance(named: name)
    content.setSearchText("")
    #expect(content.searchLabel.textColor == .labelColor)
    content.effectiveAppearance.performAsCurrentDrawingAppearance {
      let text = content.searchLabel.textColor!.usingColorSpace(.sRGB)!
      #expect(name == .darkAqua ? text.redComponent > 0.8 : text.redComponent < 0.2)
    }
    content.setSearchText("query")
    #expect(content.searchLabel.textColor == .labelColor)
  }
}

@Test @MainActor func searchHeaderCentersHintAndFillsLogoHeight() throws {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 1088, height: 300)
  content.searchIcon.image = NSImage(size: NSSize(width: 32, height: 32))
  content.layoutSubtreeIfNeeded()
  let cell = try #require(content.searchIcon.cell as? NSImageCell)
  let imageRect = cell.imageRect(forBounds: content.searchIcon.bounds)
  #expect(imageRect.height == content.searchBox.frame.height)
  #expect(content.shortcutHint.frame.height == content.shortcutHint.cell!.cellSize.height)
  #expect(content.shortcutHint.frame.midY == content.searchBox.bounds.midY)
}

@Test @MainActor func solidMaterialIsOpaqueAndSwitchingPreservesPanelContent() throws {
  _ = NSApplication.shared
  let suite = "slime.material-panel.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  settings.glassStrength = 1
  let panel = PanelWindow()
  let content = panel.content
  panel.content.setSearchText("a query")
  panel.content.setSearchFocused(true)
  panel.makeFirstResponder(content)
  let responder = panel.firstResponder
  for material in [Settings.PanelMaterial.solid, .glass, .solid] {
    settings.panelMaterial = material
    for theme in Settings.PanelBackground.allCases {
      settings.panelBackground = theme
      panel.applyGlassSettings(settings)
      let effective = settings.effectivePanelMaterial()
      #expect(panel.content === content)
      #expect(content.searchFocused)
      #expect(panel.firstResponder === responder)
      #expect(panel.content.searchLabel.stringValue == "a query")
      #expect(panel.content.searchBox.accessibilityValue() as? String == "a query")
      let color = try #require(content.layer?.backgroundColor)
      #expect(color.alpha == (effective == .solid ? 1 : 0))
      #expect(content.layer?.cornerRadius == 20)
      #expect(content.window === panel)
      if #available(macOS 26.0, *), effective == .solid {
        #expect(!panel.contentView!.subviews.contains { $0 is NSGlassEffectView })
      }
      let dark = panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      #expect(color == theme.baseColor(systemIsDark: dark)
        .withAlphaComponent(effective == .solid ? 1 : 0).cgColor)
    }
  }
}

@Test @MainActor func materialChangePreservesFilteredSelectionWithoutRefreshingWindows() throws {
  _ = NSApplication.shared
  let suite = "slime.material-session.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = PanelController(settings: settings)
  let state = State.lingering(query: "", selection: 0)
  controller.handle(state: state, effects: [])
  controller.setWindows((1...3).map {
    Window(pid: 1, windowID: UInt32($0), appName: "App", title: "Window \($0)", isMinimized: false)
  })
  controller.handle(state: state, effects: [.setQuery("w"), .focusSearchField, .moveSelection(axis: .horizontal, step: 1)])
  let selected = controller.rows[controller.selection].windowID
  var refreshes = 0
  controller.onRefresh = { refreshes += 1 }
  for material in [Settings.PanelMaterial.solid, .glass, .solid] {
    settings.panelMaterial = material
    controller.refreshAppearance()
    #expect(controller.rows[controller.selection].windowID == selected)
    #expect(controller.panel.content.searchLabel.stringValue == "w")
    #expect(controller.panel.content.searchFocused)
    #expect(refreshes == 0)
  }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func searchReusesCardsAndReleasesRemovedOrDismissedResults() async throws {
    _ = NSApplication.shared
    let panel = PanelController()
    defer { panel.dismiss() }
    let state = State.lingering(query: "", selection: 0)
    let first = window("Test", "Alpha", id: 901)
    let second = window("Test", "Beta", id: 902)
    panel.handle(state: state, effects: [])
    panel.setWindows([first, second])
    let grid = panel.panel.content.gridView
    weak var original = grid.card(for: first.windowID)
    panel.handle(state: state, effects: [.setQuery("z")])
    #expect(panel.rows.isEmpty)
    #expect(grid.card(for: first.windowID) == nil)
    #expect(original != nil, "Filtering must retain the detached card for this session")
    let renamed = window("Test", "Updated title", id: first.windowID)
    panel.setWindows([renamed, second])
    panel.handle(state: state, effects: [.setQuery("")])
    #expect(grid.card(for: first.windowID) === original)
    #expect(grid.card(for: first.windowID)?.subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "Updated title")
    panel.handle(state: state, effects: [.setQuery("z")])
    panel.setWindows([second])
    try await Task.sleep(for: .milliseconds(20))
    #expect(original == nil, "A closed window must leave the reuse pool")
    panel.handle(state: state, effects: [.setQuery("")])
    weak var remaining = grid.card(for: second.windowID)
    panel.handle(state: state, effects: [.setQuery("z")])
    #expect(remaining != nil)
    panel.dismiss()
    try await Task.sleep(for: .milliseconds(20))
    #expect(remaining == nil, "Dismissal must release filtered cards")
  }

  @Test(arguments: [false, true]) @MainActor
  func searchDoesNotReuseCardsAcrossWindowOwners(_ filtered: Bool) throws {
    _ = NSApplication.shared
    let panel = PanelController()
    defer { panel.dismiss() }
    let state = State.lingering(query: "", selection: 0)
    let first = window("Test", "Alpha", id: 903)
    panel.handle(state: state, effects: [])
    panel.setWindows([first])
    let original = try #require(panel.panel.content.gridView.card(for: first.windowID))
    if filtered { panel.handle(state: state, effects: [.setQuery("z")]) }
    let replacement = Window(pid: 2, windowID: first.windowID, appName: "Other", title: "Beta", isMinimized: false)
    panel.setWindows([replacement])
    if filtered { panel.handle(state: state, effects: [.setQuery("")]) }
    #expect(panel.panel.content.gridView.card(for: replacement.windowID) !== original)
    #expect(panel.rows == [replacement])
  }
}

extension PanelAndThumbnailTests {
@Test @MainActor func nativeSearchEditorSupportsMarkedTextReplacementAndSessionUndo() throws {
  let panel = PanelWindow()
  panel.makeKeyAndOrderFront(nil)
  defer { panel.orderOut(nil) }
  panel.content.setSearchFocused(true)
  let editor = try #require(panel.firstResponder as? NSTextView)
  #expect(editor.isEditable)
  editor.insertText("工作 Safari 🐱", replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.setSelectedRange(NSRange(location: 0, length: 2))
  editor.setMarkedText("zhou", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.hasMarkedText())
  editor.insertText("周报", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.string == "周报 Safari 🐱")
  #expect(!editor.hasMarkedText())
  editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
  editor.insertText("a\r\nb\nc", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.string == "a b c")
  #expect(editor.undoManager != nil)
}
}

extension PanelAndThumbnailTests {
@Test @MainActor func nativeCommittedQueryFiltersButCompositionAndRefreshPreserveEditor() throws {
  let controller = PanelController()
  var state = State.lingering(query: "", selection: 0)
  controller.onEvent = { event in
    let (next, effects) = reduce(state, event)
    state = next
    controller.handle(state: next, effects: effects)
  }
  let first = window("Safari", "工作", id: 901)
  let second = window("Safari", "周报", id: 902)
  controller.setWindows([first, second])
  controller.handle(state: state, effects: [.showPanel(.opt), .focusSearchField])
  defer { controller.dismiss() }
  let editor = controller.panel.content.searchEditor
  editor.insertText("工作", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(controller.rows == [first])
  editor.setSelectedRange(NSRange(location: 0, length: 2))
  editor.setMarkedText("zhou", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(controller.rows == [first])
  controller.setWindows([first, second])
  #expect(editor.hasMarkedText())
  #expect(editor.string == "zhou")
  editor.insertText("周报", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(controller.rows == [second])
  editor.insertText("missing", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
  controller.onEvent?(.enter)
  #expect(controller.panel.isVisible)
  #expect(controller.rows.isEmpty)
  #expect(controller.panel.firstResponder === editor)
  let oldQuery = editor.onQuery
  controller.dismiss()
  controller.handle(state: .lingering(query: "", selection: 0), effects: [.showPanel(.opt), .focusSearchField])
  oldQuery?("工作")
  #expect(controller.rows.count == 2)
  #expect(editor.string.isEmpty)
  #expect(!editor.hasMarkedText())
  #expect(editor.undoManager?.canUndo == false)
}
}

extension PanelAndThumbnailTests {
@Test @MainActor func clickingCardWhileMarkedActivatesCapturedIdentityAndResetsEditor() throws {
  let controller = PanelController()
  let first = window("Safari", "工作", id: 911)
  let second = window("Safari", "周报", id: 912)
  controller.setWindows([first, second])
  controller.handle(state: .lingering(query: "", selection: 0), effects: [.showPanel(.opt), .focusSearchField])
  defer { controller.dismiss() }
  var activated: Window?
  controller.onActivate = { activated = $0 }
  let editor = controller.panel.content.searchEditor
  editor.setMarkedText("zhou", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  let grid = controller.panel.content.gridView
  let card = try #require(grid.card(for: second.windowID))
  let point = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
  let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
    windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
  grid.mouseDown(with: event)
  #expect(activated == second)
  #expect(!controller.panel.isVisible)
  #expect(editor.string.isEmpty)
  #expect(!editor.hasMarkedText())
}

@Test @MainActor func nativePasteNormalizesNewlinesAndUndoRedoIsSearchScoped() throws {
  let panel = PanelWindow()
  panel.makeKeyAndOrderFront(nil)
  defer { panel.orderOut(nil) }
  panel.content.setSearchFocused(true)
  let editor = panel.content.searchEditor
  editor.insertText("工作", replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.breakUndoCoalescing()
  editor.setSelectedRange(NSRange(location: 0, length: 2))
  editor.undoManager?.endUndoGrouping()
  editor.undoManager?.beginUndoGrouping()
  // Use a private pasteboard to avoid changing the user's clipboard.
  let board = NSPasteboard.withUniqueName()
  defer { board.releaseGlobally() }
  board.setString("中文🐱\r\nSafari\n工作", forType: .string)
  #expect(editor.readSelection(from: board, type: .string))
  #expect(editor.string == "中文🐱 Safari 工作")
  editor.undoManager?.endUndoGrouping()
  editor.breakUndoCoalescing()
  editor.undoManager?.undo()
  #expect(editor.string == "工作")
  editor.undoManager?.redo()
  #expect(editor.string == "中文🐱 Safari 工作")
  editor.reset()
  #expect(editor.undoManager?.canUndo == false)
  #expect(editor.undoManager?.canRedo == false)
}
}

extension PanelAndThumbnailTests {
@Test @MainActor func nativeCommandsRespectCompositionAndModifiedArrowsAndStaySingleLine() throws {
  let panel = PanelWindow()
  panel.makeKeyAndOrderFront(nil)
  defer { panel.orderOut(nil) }
  panel.content.setSearchFocused(true)
  let editor = panel.content.searchEditor
  var commands: [Event] = []
  editor.onCommand = { commands.append($0) }
  func key(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
      windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
      isARepeat: false, keyCode: code))
  }
  editor.insertText("工作", replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.keyDown(with: try key(126, "\u{F700}", .shift))
  #expect(commands.isEmpty)
  #expect(editor.selectedRange().length > 0)
  editor.keyDown(with: try key(125, "\u{F701}"))
  #expect(commands == [.arrow(axis: .vertical, step: 1)])
  commands.removeAll()
  editor.setMarkedText("zhou", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.keyDown(with: try key(2, "d", .command))
  #expect(commands.isEmpty)
  editor.keyDown(with: try key(53, "\u{1B}"))
  #expect(commands.isEmpty)
  editor.inputContext?.discardMarkedText()
  editor.unmarkText()
  editor.setCommittedText("工作")
  editor.doCommand(by: #selector(NSTextView.insertNewline(_:)))
  #expect(editor.string == "工作")
  #expect(panel.performKeyEquivalent(with: try key(12, "q", .command)))
  #expect(editor.string == "工作")
}
}

@Test @MainActor func clickingTheEmptySearchPlaceholderTargetsTheNativeEditor() {
  let content = PanelContentView()
  content.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
  content.layoutSubtreeIfNeeded()
  let point = NSPoint(x: content.searchLabel.frame.midX + content.searchBox.frame.minX,
    y: content.searchLabel.frame.midY + content.searchBox.frame.minY)
  #expect(content.hitTest(point) === content.searchEditor)
}

extension PanelAndThumbnailTests {
@Test @MainActor func cancellingReplacementCompositionPublishesTheNativeFinalQuery() {
  let editor = SearchEditor()
  var queries: [String] = []
  editor.onQuery = { queries.append($0) }
  editor.insertText("工作 周", replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.selectAll(nil)
  editor.setMarkedText("a", selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.hasMarkedText())
  #expect(queries == ["工作 周"])
  // Input methods can cancel a replacement by clearing marked text instead of calling unmarkText.
  editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(!editor.hasMarkedText())
  #expect(editor.string.isEmpty)
  #expect(queries == ["工作 周", ""])
  editor.didChangeText()
  #expect(queries == ["工作 周", ""])
}
}
