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
  private let glass = NSGlassEffectView()
  /// lingering 下的 NSEvent 翻译入口（spec §6：两个事件源、一个状态机）。
  var onKey: (@MainActor (Event) -> Void)?
  /// 失去 key（用户点了别的窗口）—— 面板该藏着走，避免留下无主窗口。
  var onResignKey: (@MainActor () -> Void)?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 160),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
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

  /// 玻璃参数由设置驱动。内容**必须**挂在 `glass.contentView` 上 ——
  /// 头文件明说任意子视图的 z-order 不保证（spec §7）。
  ///
  /// shortcut: 只有一块玻璃面，没用 NSGlassEffectContainerView —— 每张卡片
  ///           单独做玻璃时再回来合并渲染（spec §14）
  func applyGlassSettings(_ settings: Settings) {
    glass.style = settings.glassStyle.glassEffectStyle
    glass.tintColor = settings.glassTint
    glass.cornerRadius = settings.glassCornerRadius
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    if let translated = Self.translate(event), let onKey {
      onKey(translated)
      return
    }
    // 不是我们认识的键（功能键等）：不动。0.0.1 面板没有别的按键消费者。
    super.keyDown(with: event)
  }

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }

  /// NSEvent → Event。翻译的活在这里，不在 Core/Trigger；
  /// keyCode 表与 EventTap 共用（KeyTable），两个事件源语义一致。
  private static func translate(_ event: NSEvent) -> Event? {
    guard event.type == .keyDown else { return nil }
    let flags = event.modifierFlags
    return KeyTable.event(
      keyCode: Int(event.keyCode),
      shift: flags.contains(.shift),
      commandOrOption: flags.contains(.command) || flags.contains(.option),
      character: event.charactersIgnoringModifiers?.first
    )
  }
}

/// 面板内容：搜索行 + 卡片网格 + 空态提示。手动布局（从上到下三块，
/// 用 constraints 是杀鸡用牛刀）。
final class PanelContentView: NSView {
  let searchBox = NSView()
  let searchIcon = NSImageView()
  let searchLabel = NSTextField(labelWithString: "")
  let scrollView = NSScrollView()
  let gridView = CardGridView()
  let emptyLabel = NSTextField(labelWithString: "没有其他窗口")

  /// 空查询时的占位提示。键盘路径上查询只经 `setSearchText` 更新，
  /// 这里就是它的初始状态。
  static let searchPlaceholder = "输入以过滤"

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
    searchBox.layer?.cornerRadius = 8
    searchBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
    searchIcon.contentTintColor = .secondaryLabelColor
    searchIcon.imageScaling = .scaleProportionallyUpOrDown
    searchLabel.font = .systemFont(ofSize: 15)
    searchLabel.lineBreakMode = .byTruncatingTail
    setSearchText("")
    searchBox.addSubview(searchIcon)
    searchBox.addSubview(searchLabel)

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
  }

  required init?(coder: NSCoder) { fatalError("面板只从代码建") }

  /// 空查询显示占位提示（secondaryLabelColor），有查询显示查询文本
  /// （labelColor）。文本与纯状态机的 query 永远一致（design.md）。
  func setSearchText(_ text: String) {
    let isEmpty = text.isEmpty
    searchLabel.stringValue = isEmpty ? Self.searchPlaceholder : text
    searchLabel.textColor = isEmpty ? .secondaryLabelColor : .labelColor
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
    searchLabel.frame = NSRect(
      x: textX,
      y: (searchHeight - searchLabel.frame.height) / 2,
      width: searchBox.bounds.width - textX - Self.searchLeadingInset,
      height: searchLabel.frame.height
    )

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
