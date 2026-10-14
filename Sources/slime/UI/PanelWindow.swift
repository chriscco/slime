import AppKit

/// nonactivating 高层级面板（spec §4 的硬约束：切换器自己不能抢焦点）。
///
/// 无边框窗口默认不能成为 key，覆写 `canBecomeKey` —— `nonactivatingPanel`
/// 保证「成为 key 而不激活 app」，但 key 状态本身要显式允许，否则
/// lingering 的打字进不来。
final class PanelWindow: NSPanel {
  /// 面板内容，PanelController 从这里摸控件。
  let content = PanelContentView()
  /// 玻璃面：内容**必须**挂在它的 `contentView` 里（spec §7）。
  ///
  /// shortcut: 只有一块玻璃面，没用 NSGlassEffectContainerView —— 每张卡片
  ///           单独做玻璃时再回来合并渲染
  private let glass = NSGlassEffectView()
  /// 失去 key（用户点了别的窗口）—— 面板该藏着走，避免留下无主窗口。
  var onResignKey: (@MainActor () -> Void)?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 160),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    appearance = NSAppearance(named: .darkAqua)
    isFloatingPanel = true
    level = .floating
    becomesKeyOnlyIfNeeded = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    // 关掉系统的出场动画：默认行为会让整块面板（含图标/文字）在展示时
    // 从 ~98% 缩放到位，用户看到的是「图标闪一下」（每一次召出都会）。
    animationBehavior = .none
    hasShadow = true
    isOpaque = false
    backgroundColor = .clear
    // 所有 Space 都能出现、全屏应用上也浮着、不进窗口循环。
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

    // 窗口本身透明；圆角和背景都归玻璃视图（applyGlassSettings）。内容挂在
    // 玻璃的 contentView 里，不做玻璃的兄弟节点 —— 头文件明说任意子视图的
    // z-order 不保证（spec §7）。
    contentView = glass
    glass.contentView = content
    // 头文件只保证 contentView 被放进玻璃、不保证自动撑满 —— 尺寸传导
    // 无论如何都要成立；原生行为若已自动撑满，这行也无副作用。
    content.autoresizingMask = [.width, .height]
    // 内容层留着裁边：空态文字不越出面板边界。
    content.wantsLayer = true
    content.layer?.masksToBounds = true
  }

  /// 面板底色。**固定常量** —— 这一版不允许改背景色（spec §3 非目标），
  /// 浓度是它的 alpha 表达的。
  private static let panelBase = NSColor.black

  /// 玻璃参数由设置驱动。内容**必须**挂在 `glass.contentView` 上 ——
  /// 头文件明说任意子视图的 z-order 不保证（spec §7）。
  ///
  /// 浓度不是玻璃的属性：`NSGlassEffectView` 没有 opacity，`tintColor` 的 alpha
  /// 实测无效（spec §7 那张五个 alpha 长得一模一样的截图）。做法是在玻璃之上、
  /// 内容之下盖一层实色遮罩，`alpha = 1 − 浓度` —— 背后的内容跟着变淡，
  /// 而卡片上的文字图标是内容视图的子视图，不受影响。
  ///
  /// shortcut: 玻璃浓度是一层遮罩，不是玻璃本身的属性（NSGlassEffectView 没有
  ///           opacity，tintColor 的 alpha 实测无效）—— Apple 给出真属性时换掉
  func applyGlassSettings(_ settings: Settings) {
    glass.style = settings.glassStyle.glassEffectStyle
    glass.cornerRadius = settings.glassCornerRadius
    // 遮罩是方的，玻璃是圆的：不给内容层同样的圆角，四角会露出黑方块。
    content.layer?.cornerRadius = settings.glassCornerRadius
    content.layer?.backgroundColor = Self.panelBase
      .withAlphaComponent(1 - settings.glassStrength).cgColor
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  // The tap owns keyboard sessions; do not run a second reducer in AppKit.
  override func keyDown(with event: NSEvent) {}

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }


}

/// 面板内容：搜索行 + 卡片网格 + 空态提示。手动布局（从上到下三块，
/// 用 constraints 是杀鸡用牛刀）。
final class PanelContentView: NSView {
  let searchBox = NSView()
  let searchIcon = NSImageView()
  let searchLabel = NSTextField(labelWithString: "")
  let searchCaret = NSView()
  private let searchClip = NSView()
  private(set) var searchFocused = false
  private var searchText = ""
  var accentColor = Settings.defaultHighlightColor

  let scrollView = NSScrollView()
  let gridView = CardGridView()
  let emptyLabel = NSTextField(labelWithString: "")
  let statusLabel = NSTextField(labelWithString: "")

  /// 空查询时的占位提示。键盘路径上查询只经 `setSearchText` 更新，
  /// 这里就是它的初始状态。
  static var searchPlaceholder: String { localized("Type to filter", "输入以过滤") }

  override var isFlipped: Bool { true }

  /// 手动布局的尺寸全部取自 GridLayout —— 面板整体尺寸（panelWidth /
  /// panelHeight）也是它算的，内容视图再自带一组 padding / headerHeight
  /// 就会把文档视图摆偏（同一份常量只能有一个来源）。
  private static let metrics = GridLayout(count: 0)
  private static let searchIconSide: CGFloat = 14
  private static let searchLeadingInset: CGFloat = 10
  /// 放大镜与查询文本之间的间隙。
  private static let searchIconGap: CGFloat = 6

  init() {
    super.init(frame: .zero)

    // 无框搜索行：半透明浅色 pill，没有硬边 —— 底下的玻璃面继续活着，
    // 不用 controlBackgroundColor 那种实心方块（用户实测：黑框很突兀）。
    searchBox.wantsLayer = true
    searchBox.layer?.cornerRadius = 10
    searchBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
    searchIcon.contentTintColor = .secondaryLabelColor
    searchIcon.imageScaling = .scaleProportionallyUpOrDown
    searchLabel.font = .systemFont(ofSize: 15)
    searchLabel.lineBreakMode = .byTruncatingTail
    setSearchText("")
    searchBox.addSubview(searchIcon)
    searchClip.wantsLayer = true
    searchClip.layer?.masksToBounds = true
    searchBox.addSubview(searchClip)
    searchClip.addSubview(searchLabel)
    searchCaret.wantsLayer = true
    searchCaret.layer?.cornerRadius = 1
    searchCaret.isHidden = true
    searchClip.addSubview(searchCaret)
    searchBox.setAccessibilityRole(.textField)
    searchBox.setAccessibilityLabel(localized("Search windows", "搜索窗口"))

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = gridView
    scrollView.borderType = .noBorder

    emptyLabel.font = .systemFont(ofSize: 14)
    emptyLabel.textColor = .secondaryLabelColor
    emptyLabel.isHidden = true

    addSubview(searchBox)
    addSubview(scrollView)
    addSubview(emptyLabel)
    statusLabel.font = .systemFont(ofSize: 11)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.alignment = .right
    statusLabel.lineBreakMode = .byTruncatingTail
    searchBox.addSubview(statusLabel)
  }

  required init?(coder: NSCoder) { fatalError("面板只从代码建") }

  /// 空查询显示占位提示（secondaryLabelColor），有查询显示查询文本
  /// （labelColor）。文本与纯状态机的 query 永远一致（design.md）。
  func setSearchText(_ text: String) {
    let value = text.isEmpty ? Self.searchPlaceholder : text
    guard searchText != text || searchLabel.stringValue != value else { return }
    searchText = text
    let isEmpty = text.isEmpty
    searchLabel.stringValue = isEmpty ? Self.searchPlaceholder : text
    searchLabel.textColor = isEmpty ? .secondaryLabelColor : .labelColor
    searchBox.setAccessibilityValue(text)
    needsLayout = true
  }

  func setSearchFocused(_ focused: Bool) {
    guard focused != searchFocused else { return }
    searchFocused = focused
    searchBox.layer?.borderWidth = focused ? 2 : 0
    searchBox.layer?.borderColor = accentColor.withAlphaComponent(0.85).cgColor
    searchBox.layer?.backgroundColor = (focused ? accentColor.withAlphaComponent(0.10)
      : NSColor.white.withAlphaComponent(0.06)).cgColor
    searchIcon.contentTintColor = focused ? accentColor : .secondaryLabelColor
    searchCaret.layer?.backgroundColor = accentColor.cgColor
    searchCaret.isHidden = !focused
    searchCaret.layer?.removeAllAnimations()
    if focused && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let blink = CAKeyframeAnimation(keyPath: "opacity")
      blink.values = [1, 1, 0, 0, 1]
      blink.keyTimes = [0, 0.45, 0.5, 0.95, 1]
      blink.duration = 1.2; blink.repeatCount = .infinity
      searchCaret.layer?.add(blink, forKey: "blink")
    }
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  func showStatus(_ message: String?) {
    statusLabel.stringValue = message ?? ""
    statusLabel.toolTip = message
    statusLabel.setAccessibilityLabel(message)
    needsLayout = true
  }

  /// 渲染一批卡片：先把文档宽度定稿（跑一遍布局、经 setContentWidth 传导），
  /// 再赋给 `gridView` —— 任何一次 rows 赋值（rebuild）拿到的 contentWidth
  /// 都必须是最终值。连拍里「面板出现后尺寸再跳」的残余就出在这里（issue #35）。
  /// 面板尺寸由调用方先定稿（`PanelController.resizeAndPosition`），玻璃 /
  /// 内容的 bounds 传导见调用点。
  func render(rows: [Window]) {
    layoutSubtreeIfNeeded()
    gridView.rows = rows
    // rows 换了 → 文档高度换了（4 排起要滚动），而文档高度会影响 scrollView
    // 的 contentSize（竖条 reserve）——同帧内再跑一遍，把二次修正收在这一帧里，
    // 而不是留给下一帧。
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  override func layout() {
    super.layout()
    let padding = CGFloat(Self.metrics.padding)
    let headerHeight = CGFloat(Self.metrics.headerHeight)
    // headerHeight = 搜索行 + 它下方的间隙；文档视图从 padding + headerHeight
    // 起，面板高度公式（panelHeight）才对得上。
    let searchHeight = headerHeight - padding
    let inner = bounds.width - padding * 2
    searchBox.frame = NSRect(x: padding, y: padding, width: inner, height: searchHeight)
    searchIcon.frame = NSRect(
      x: Self.searchLeadingInset,
      y: (searchHeight - Self.searchIconSide) / 2,
      width: Self.searchIconSide,
      height: Self.searchIconSide)
    searchLabel.sizeToFit()
    let textX = Self.searchLeadingInset + Self.searchIconSide + Self.searchIconGap
    let available = max(0, (searchBox.bounds.width - textX - Self.searchLeadingInset)
      * (statusLabel.stringValue.isEmpty ? 1 : 0.45))
    searchClip.frame = NSRect(x: textX, y: 0, width: available, height: searchHeight)
    let textWidth = ceil((searchText as NSString).size(withAttributes:
      [.font: searchLabel.font ?? NSFont.systemFont(ofSize: 15)]).width)
    let offset = min(0, available - textWidth - 6)
    searchLabel.frame = NSRect(x: offset, y: (searchHeight - searchLabel.frame.height) / 2,
      width: max(available, textWidth + 4), height: searchLabel.frame.height)
    searchCaret.frame = NSRect(x: max(0, offset + textWidth + 2),
      y: (searchHeight - 18) / 2, width: 2, height: 18)

    statusLabel.frame = NSRect(x: searchBox.bounds.width * 0.48, y: (searchHeight - 16) / 2,
      width: searchBox.bounds.width * 0.52 - 10, height: 16)
    let listTop = padding + headerHeight
    scrollView.frame = NSRect(
      x: padding, y: listTop, width: inner, height: bounds.height - listTop - padding)
    // document view 不会自己撑开：宽度必须从 scroll view 传下去。
    gridView.setContentWidth(scrollView.contentSize.width)
    emptyLabel.sizeToFit()
    emptyLabel.frame = NSRect(
      x: padding + 8, y: listTop + 6, width: inner - 16, height: emptyLabel.frame.height)
  }
}
