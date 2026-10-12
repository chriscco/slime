import AppKit

/// 卡片网格：图标在上、窗口名在下，一排最多 5 张（spec §5）。
///
/// 不用 `NSCollectionView`：这里不要 cell 复用、不要它自带的选中样式和布局系统，
/// 手动布局反而更可控 —— 高亮就是网格里的一个普通子视图，跟着滚动走，
/// 不需要和集合视图内部的坐标系跨层。（0.0.1 的列表也是这个理由，
/// 见 docs/modules/panel/decision.md。）
final class CardGridView: NSView {
  /// 渲染的卡片。由 PanelController 推过来（rank 结果）。
  var rows: [Window] = [] {
    didSet { rebuild() }
  }

  private(set) var layout = GridLayout(count: 0)
  private(set) var selection = 0

  private let highlight = HighlightView()
  private var cards: [CardView] = []
  /// scroll view 传下来的内容宽度。宽度为 0 时卡片的 frame 宽度是负的，
  /// 什么都画不出来 —— 0.0.1 就是栽在这里（issue #15）。
  private var contentWidth: CGFloat = 0

  override var isFlipped: Bool { true }

  init() {
    super.init(frame: .zero)
    addSubview(highlight, positioned: .below, relativeTo: nil)
  }

  required init?(coder: NSCoder) { fatalError("网格只从代码建") }

  /// document view 的宽度跟着 scroll view 的内容宽度走（高度由行数决定）。
  func setContentWidth(_ width: CGFloat) {
    guard contentWidth != width else { return }
    contentWidth = width
    applyLayout()
  }

  /// 选中移动。`animated` 只给键盘移动用 —— 刷新重建时不闪。
  func setSelection(_ index: Int, animated: Bool) {
    let previous = selection
    selection = index
    highlight.isHidden = rows.isEmpty
    guard !rows.isEmpty else { return }

    let target = highlightRect(index)
    // 跨行超过一排时直接跳：高亮斜穿整个面板看起来像坏了（spec §10）。
    if animated && layout.shouldAnimate(from: previous, to: index) {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        highlight.animator().frame = target
      }
    } else {
      highlight.frame = target
    }
  }

  /// 把选中项滚进可见范围（循环到列表两端时）。
  func scrollSelectionToVisible() {
    guard !rows.isEmpty else { return }
    scrollToVisible(highlightRect(selection))
  }

  private func highlightRect(_ index: Int) -> NSRect {
    let origin = layout.origin(of: index)
    // 比卡片大一圈，卡片整个落在高亮上。
    let inset: CGFloat = 4
    return NSRect(
      x: origin.x - inset,
      y: origin.y - inset,
      width: layout.cardWidth + inset * 2,
      height: layout.cardHeight + inset * 2
    )
  }

  private func rebuild() {
    cards.forEach { $0.removeFromSuperview() }
    cards = rows.map { CardView(window: $0) }
    cards.forEach(addSubview)
    layout = GridLayout(count: rows.count)
    applyLayout()
  }

  private func applyLayout() {
    for (index, card) in cards.enumerated() {
      let origin = layout.origin(of: index)
      card.frame = NSRect(
        x: origin.x, y: origin.y,
        width: layout.cardWidth, height: layout.cardHeight)
    }
    // 宽度以 scroll view 为准（不为 0 时），高度用文档视图的**完整**行数 ——
    // 只算 visibleRows 的话第 4 排以后滚不到（spec §12）。
    frame.size = NSSize(
      width: contentWidth > 0 ? contentWidth : layout.gridWidth,
      height: layout.contentHeight)
    highlight.frame = highlightRect(selection)
  }
}

/// 一张卡片：上面 app 图标，下面窗口名。
///
/// 标签只显示**窗口标题**，不显示 app 名 —— 图标已经说明是哪个 app 了，
/// 而 112pt 宽塞不下 `app名 — 标题`。标题为空时退回 app 名。
/// internal 而不是 private：PanelLayoutTests 要能 cast 到它。
final class CardView: NSView {
  private static let iconSide: CGFloat = 64
  private static let labelHeight: CGFloat = 16
  private static let labelGap: CGFloat = 4

  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")

  /// 未翻转的坐标系里 `layout()` 会画反（label 在上）—— spec §2 要求图标在上。
  override var isFlipped: Bool { true }

  init(window: Window) {
    super.init(frame: .zero)
    icon.image = AppIcons.icon(for: window)
    icon.imageScaling = .scaleProportionallyUpOrDown
    label.stringValue = window.title.isEmpty ? window.appName : window.title
    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.drawsBackground = false
    label.isBordered = false
    addSubview(icon)
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError("卡片只从代码建") }

  override func layout() {
    super.layout()
    icon.frame = NSRect(
      x: (bounds.width - Self.iconSide) / 2,
      y: Self.labelGap,
      width: Self.iconSide,
      height: Self.iconSide)
    label.frame = NSRect(
      x: 6,
      y: Self.labelGap + Self.iconSide + Self.labelGap,
      width: max(0, bounds.width - 12),
      height: Self.labelHeight)
  }
}

/// 高亮条：圆角、系统强调色。动画由 `CardGridView.setSelection` 驱动。
final class HighlightView: NSView {
  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    // 半透明：卡片文字保持 labelColor 不换色，对比度也够。
    layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35)
      .cgColor
  }

  required init?(coder: NSCoder) { fatalError("高亮条只从代码建") }
}
