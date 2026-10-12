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

/// 面板内容：搜索框 + 竖向列表 + 空态提示。手动布局（从上到下三块，
/// 用 constraints 是杀鸡用牛刀）。
final class PanelContentView: NSView {
  let searchBox = NSView()
  let searchLabel = NSTextField(labelWithString: "")
  let scrollView = NSScrollView()
  let listView = WindowListDocumentView()
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
    scrollView.documentView = listView
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
    listView.setContentWidth(scrollView.contentSize.width)
    emptyLabel.sizeToFit()
    emptyLabel.frame = NSRect(
      x: Self.padding + 8, y: listTop + 6, width: inner - 16, height: emptyLabel.frame.height)
  }
}

/// 竖向列表：手动布局的行 + 平滑滑动的高亮条。
///
/// 不用 NSTableView：这里不要列、不要复用、不要它自带的选中样式，
/// 手动布局反而更可控 —— 高亮就是 document view 里的一个普通子视图，
/// 跟着滚动走，不需要和表格内部的坐标系跨层。
final class WindowListDocumentView: NSView {
  static let rowHeight: CGFloat = 26

  /// 渲染的行。由 PanelController 推过来（rank 结果）。
  var rows: [Window] = [] {
    didSet { rebuild() }
  }

  private(set) var selection = 0
  private let highlight = HighlightView()
  private var labels: [NSTextField] = []

  override var isFlipped: Bool { true }

  init() {
    super.init(frame: .zero)
    addSubview(highlight, positioned: .below, relativeTo: nil)
  }

  required init?(coder: NSCoder) { fatalError("列表只从代码建") }

  /// document view 的宽度跟着 scroll view 的内容宽度走（高度由行数决定）。
  /// 宽度变化经 resizeSubviews 传导到每一行 —— 没有这一步，document view
  /// 宽度是 0，行的 frame 宽度为负，文字画不出来（面板看起来是空白的）。
  func setContentWidth(_ width: CGFloat) {
    guard frame.width != width else { return }
    frame.size.width = width
  }

  /// 选中移动。`animated` 只给键盘移动用 —— 刷新重建时不闪。
  func setSelection(_ index: Int, animated: Bool) {
    selection = index
    highlight.isHidden = rows.isEmpty
    guard !rows.isEmpty else { return }
    let rect = rowRect(index)
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.09
        highlight.animator().frame = rect
      }
    } else {
      highlight.frame = rect
    }
  }

  /// 把选中行滚进可见范围（循环到列表两端时）。
  func scrollSelectionToVisible() {
    guard !rows.isEmpty else { return }
    scrollToVisible(rowRect(selection))
  }

  private func rowRect(_ index: Int) -> NSRect {
    NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
  }

  private func rebuild() {
    labels.forEach { $0.removeFromSuperview() }
    labels = rows.map { window in
      let label = NSTextField(labelWithString: window.label)
      label.font = .systemFont(ofSize: 14)
      label.textColor = .labelColor
      label.lineBreakMode = .byTruncatingMiddle
      label.drawsBackground = false
      label.isBordered = false
      addSubview(label)
      return label
    }
    frame.size = NSSize(
      width: bounds.width, height: CGFloat(rows.count) * Self.rowHeight)
    for (index, label) in labels.enumerated() {
      let rect = rowRect(index).insetBy(dx: 10, dy: 0)
      label.sizeToFit()
      label.frame = NSRect(
        x: rect.minX,
        y: rect.minY + (Self.rowHeight - label.frame.height) / 2,
        width: rect.width,
        height: label.frame.height
      )
    }
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    super.resizeSubviews(withOldSize: oldSize)
    // 宽度变化（面板尺寸调整）时行要跟着撑满。
    for (index, label) in labels.enumerated() {
      let rect = rowRect(index).insetBy(dx: 10, dy: 0)
      label.frame.size.width = rect.width
    }
    highlight.frame.size.width = bounds.width
  }
}

/// 高亮条：圆角、系统强调色。动画由外部用 animator() 驱动。
final class HighlightView: NSView {
  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 6
    // 半透明：行文字保持 labelColor 不换色，对比度也够。深浅手动验收时再调。
    layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35)
      .cgColor
  }

  required init?(coder: NSCoder) { fatalError("高亮条只从代码建") }
}
