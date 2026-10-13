import AppKit

/// 卡片网格：图标在上、窗口名在下，一排最多 4 张（spec §5）。
///
/// 不用 `NSCollectionView`：这里不要 cell 复用、不要它自带的选中样式和布局系统，
/// 手动布局反而更可控 —— 高亮就是网格里的一个普通子视图，跟着滚动走，
/// 不需要和集合视图内部的坐标系跨层。（0.0.1 的列表也是这个理由，
/// 见 docs/modules/panel/decision.md。）
final class CardGridView: NSView {
  /// 渲染的卡片。由 PanelController 推过来（rank 结果）。
  ///
  /// 刷新按身份收敛（issue #35 的闪烁根因）：windowID 序列一致 → 不重建、
  /// 不动 layout / selection，只就地刷新内容；不一致 → 复用存活窗口的
  /// `CardView`、按新顺序重排，只对新增/消失的做增删。
  var rows: [Window] = [] {
    didSet {
      if rows.map(\.windowID) == oldValue.map(\.windowID) {
        for (window, card) in zip(rows, cards) { card.update(window: window) }
        return
      }
      rebuild(using: oldValue)
    }
  }

  private(set) var layout = GridLayout(count: 0)
  private(set) var selection = 0

  /// 高亮色（spec §8）。PanelController 在 show() 里推一次，同玻璃参数。
  var highlightColor: NSColor {
    get { highlight.color }
    set { highlight.color = newValue }
  }

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
    // 贴合卡片本身，不外扩：document view 边缘不再裁到高亮，四边留白也均匀。
    let origin = layout.origin(of: index)
    return NSRect(
      x: origin.x,
      y: origin.y,
      width: layout.cardWidth,
      height: layout.cardHeight
    )
  }

  /// 行集变了：按 windowID 把上一轮的卡片收进池子，存活的就地更新后按新顺序
  /// 重排；池子里剩下的（消失的窗口）才移除、没命中的才新建。windowID 是
  /// 窗口的身份（design.md），假设唯一。
  private func rebuild(using previous: [Window]) {
    var pool: [UInt32: CardView] = [:]
    for (window, card) in zip(previous, cards) {
      pool[window.windowID] = card
    }

    var next: [CardView] = []
    next.reserveCapacity(rows.count)
    for window in rows {
      if let card = pool.removeValue(forKey: window.windowID) {
        card.update(window: window)
        next.append(card)
      } else {
        let card = CardView(window: window)
        addSubview(card)
        next.append(card)
      }
    }
    for card in pool.values { card.removeFromSuperview() }

    cards = next
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

/// 一张卡片：上面窗口缩略图（抓不到就是 app 图标），下面窗口名。
///
/// 标签只显示**窗口标题**，不显示 app 名 —— 缩略图已经说明是哪个 app 了，
/// 而 160pt 宽塞不下 `app名 — 标题`。标题为空时退回 app 名。
/// internal 而不是 private：PanelLayoutTests 要能 cast 到它。
final class CardView: NSView {
  private static let labelHeight: CGFloat = 16
  /// 缩略图与文字的间隙。
  private static let thumbGap: CGFloat = 4
  /// 文字左右的内边距。
  private static let labelSidePadding: CGFloat = 6
  /// 高亮的 2.5pt 描边画在**单元格边界**上（见 highlightRect）—— 卡片内容
  /// 再内缩这么多，描边就不会压在缩略图或底部标题上（用户实测：重叠）。
  private static let contentInset: CGFloat = 7

  private let thumb = NSImageView()
  private let label = NSTextField(labelWithString: "")

  /// 未翻转的坐标系里 `layout()` 会画反（label 在上）—— spec §2 要求图在上。
  override var isFlipped: Bool { true }

  init(window: Window) {
    super.init(frame: .zero)
    // 静态配置只做一次；图与标题走 update（刷新复用路径也走它）。
    // 按长宽比缩放整窗可见（不裁切、不拉伸），多出来的边露出面板底色。
    thumb.imageScaling = .scaleProportionallyUpOrDown
    thumb.wantsLayer = true
    thumb.layer?.cornerRadius = 6
    thumb.layer?.masksToBounds = true
    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.drawsBackground = false
    label.isBordered = false
    addSubview(thumb)
    addSubview(label)
    update(window: window)
  }

  required init?(coder: NSCoder) { fatalError("卡片只从代码建") }

  /// 就地更新：缩略图（退回 app 图标）+ 标题（标题为空时退回 app 名）。
  func update(window: Window) {
    // 降级链是「缩略图 → app 图标」：抓不到图的情况包括没权限、抓失败、
    // 台前调度搁置（spec §4.5）。**卡片尺寸不变**，混排时不该有两种卡形。
    // 缩略图给的是 CGImage（System/ 不碰 AppKit，brief 的 `??` 直接赋值
    // 在这里编不过），进视图前转成 NSImage。
    thumb.image =
      WindowThumbnails.image(for: window)
      .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
      ?? AppIcons.icon(for: window)
    label.stringValue = window.title.isEmpty ? window.appName : window.title
  }

  override func layout() {
    super.layout()
    let inset = Self.contentInset
    thumb.frame = NSRect(
      x: inset, y: inset,
      width: max(0, bounds.width - inset * 2),
      height: max(0, bounds.height - Self.labelHeight - Self.thumbGap - inset * 2))
    label.frame = NSRect(
      x: Self.labelSidePadding,
      y: bounds.height - Self.labelHeight - Self.contentInset,
      width: max(0, bounds.width - Self.labelSidePadding * 2),
      height: Self.labelHeight)
  }
}

/// 高亮：设定色的 2.5pt 轮廓 + 8% 同色填充，贴合卡片尺寸（动画由
/// `CardGridView.setSelection` 驱动）。
final class HighlightView: NSView {
  private static let cornerRadius: CGFloat = 12
  /// 线条粗细（spec §8：0.0.2 是 2）。
  private static let borderWidth: CGFloat = 2.5

  /// 线条颜色。**不绑系统主题色**（spec §8），面板 `show()` 时推一次 ——
  /// 不是动态色，所以不需要 `viewDidChangeEffectiveAppearance` 那套重解析。
  var color: NSColor = Settings.defaultHighlightColor {
    didSet { applyColor() }
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.borderWidth = Self.borderWidth
    applyColor()
  }

  required init?(coder: NSCoder) { fatalError("高亮条只从代码建") }

  /// 外圈轮廓 + 极轻填充：文字保持 labelColor 不换色，玻璃面透上来。
  private func applyColor() {
    layer?.borderColor = color.cgColor
    layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
  }
}
