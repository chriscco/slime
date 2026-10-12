import AppKit

/// nonactivating 高层级面板（spec §4 的硬约束：切换器自己不能抢焦点）。
///
/// 无边框窗口默认不能成为 key，覆写 `canBecomeKey` —— `nonactivatingPanel`
/// 保证「成为 key 而不激活 app」，但 key 状态本身要显式允许，否则
/// lingering 的打字进不来。
final class PanelWindow: NSPanel {
  /// 面板内容，PanelController 从这里摸控件。
  let content = PanelContentView()
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

    contentView = content
    // 圆角靠 content view 的 layer；窗口本身透明。
    content.wantsLayer = true
    content.layer?.cornerRadius = 12
    content.layer?.masksToBounds = true
    content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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

  static let searchHeight: CGFloat = 34
  static let padding: CGFloat = 10

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
    let inner = bounds.width - Self.padding * 2
    searchBox.frame = NSRect(
      x: Self.padding, y: Self.padding, width: inner, height: Self.searchHeight)
    searchLabel.frame = searchBox.bounds.insetBy(dx: 8, dy: 0)
    searchLabel.sizeToFit()
    searchLabel.frame = NSRect(
      x: 8,
      y: (Self.searchHeight - searchLabel.frame.height) / 2,
      width: searchBox.bounds.width - 16,
      height: searchLabel.frame.height
    )

    let listTop = Self.padding + Self.searchHeight + Self.padding
    scrollView.frame = NSRect(
      x: Self.padding, y: listTop, width: inner, height: bounds.height - listTop - Self.padding)
    // document view 不会自己撑开：宽度必须从 scroll view 传下去。
    gridView.setContentWidth(scrollView.contentSize.width)
    emptyLabel.sizeToFit()
    emptyLabel.frame = NSRect(
      x: Self.padding + 8, y: listTop + 6, width: inner - 16, height: emptyLabel.frame.height)
  }
}
