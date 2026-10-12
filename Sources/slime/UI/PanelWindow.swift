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

/// 面板内容：搜索框 + 卡片网格 + 空态提示。手动布局（从上到下三块，
/// 用 constraints 是杀鸡用牛刀）。
final class PanelContentView: NSView {
  let searchBox = NSView()
  let searchLabel = NSTextField(labelWithString: "")
  let scrollView = NSScrollView()
  let gridView = CardGridView()
  let emptyLabel = NSTextField(labelWithString: "没有其他窗口")

  override var isFlipped: Bool { true }

  /// 手动布局的尺寸全部取自 GridLayout —— 面板整体尺寸（panelWidth /
  /// panelHeight）也是它算的，内容视图再自带一组 padding / headerHeight
  /// 就会把文档视图摆偏（同一份常量只能有一个来源）。
  private static let metrics = GridLayout(count: 0)

  init() {
    super.init(frame: .zero)

    searchBox.wantsLayer = true
    searchBox.layer?.cornerRadius = 8
    searchBox.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    searchLabel.font = .systemFont(ofSize: 15)
    searchLabel.textColor = .labelColor
    searchLabel.lineBreakMode = .byTruncatingTail
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

  override func layout() {
    super.layout()
    let padding = CGFloat(Self.metrics.padding)
    let headerHeight = CGFloat(Self.metrics.headerHeight)
    // headerHeight = 搜索框 + 它下方的间隙；文档视图从 padding + headerHeight
    // 起，面板高度公式（panelHeight）才对得上。
    let searchHeight = headerHeight - padding
    let inner = bounds.width - padding * 2
    searchBox.frame = NSRect(x: padding, y: padding, width: inner, height: searchHeight)
    searchLabel.frame = searchBox.bounds.insetBy(dx: 8, dy: 0)
    searchLabel.sizeToFit()
    searchLabel.frame = NSRect(
      x: 8,
      y: (searchHeight - searchLabel.frame.height) / 2,
      width: searchBox.bounds.width - 16,
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
