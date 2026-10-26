import AppKit

/// nonactivating 高层级面板（spec §4 的硬约束：切换器自己不能抢焦点）。
///
/// 无边框窗口默认不能成为 key，覆写 `canBecomeKey` —— `nonactivatingPanel`
/// 保证「成为 key 而不激活 app」，但 key 状态本身要显式允许，否则
/// lingering 的打字进不来。
final class PanelWindow: NSPanel {
  /// 面板内容，PanelController 从这里摸控件。
  let content = PanelContentView()
  // Keep the window's root stable while moving content between material hosts.
  private let root = NSView()
  private var glassHost: NSView?
  private var material = Settings.PanelMaterial.solid
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

    root.frame = NSRect(origin: .zero, size: frame.size)
    contentView = root
    content.frame = root.bounds
    root.addSubview(content)
    content.autoresizingMask = [.width, .height]
    // 内容层留着裁边：空态文字不越出面板边界。
    content.wantsLayer = true
    content.layer?.masksToBounds = true
    content.onAppearanceChange = { [weak self] in self?.refreshBackground() }
  }

  private var panelBackground = Settings.PanelBackground.black
  private var glassStrength = Settings.defaultGlassStrength

  private func refreshBackground() {
    let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    content.layer?.backgroundColor = panelBackground.baseColor(systemIsDark: dark)
      .withAlphaComponent(material == .solid ? 1 : 1 - glassStrength).cgColor
  }

  func applyGlassSettings(_ settings: Settings) {
    material = settings.effectivePanelMaterial()
    panelBackground = settings.panelBackground
    glassStrength = settings.glassStrength
    appearance = panelBackground == .system ? nil
      : NSAppearance(named: panelBackground == .white ? .aqua : .darkAqua)
    if #available(macOS 26.0, *) {
      if material == .glass {
        if glassHost == nil {
          let responder = firstResponder
          let glass = NSGlassEffectView(frame: root.bounds)
          glass.autoresizingMask = [.width, .height]
          content.removeFromSuperview()
          root.addSubview(glass)
          glass.contentView = content
          content.frame = glass.bounds
          glassHost = glass
          makeFirstResponder(responder)
        }
        if let glass = glassHost as? NSGlassEffectView {
          glass.style = settings.glassStyle.glassEffectStyle
          glass.cornerRadius = settings.glassCornerRadius
        }
      } else if let glass = glassHost as? NSGlassEffectView {
        let responder = firstResponder
        glass.contentView = nil
        glass.removeFromSuperview()
        glassHost = nil
        content.frame = root.bounds
        root.addSubview(content)
        makeFirstResponder(responder)
      }
    }
    content.layer?.cornerRadius = settings.glassCornerRadius
    refreshBackground()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  // The editor sends panel commands to the tap-owned reducer.
  override func keyDown(with event: NSEvent) {}

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }


}

/// 面板内容：搜索行 + 卡片网格 + 空态提示。手动布局（从上到下三块，
/// 用 constraints 是杀鸡用牛刀）。
final class PanelContentView: NSView {
  var onAppearanceChange: (() -> Void)?

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshSearchPalette()
    onAppearanceChange?()
  }

  let searchBox = NSView()
  let searchIcon = NSImageView()
  let searchEditor = SearchEditor()
  let searchLabel = NSTextField(labelWithString: "")
  private let searchClip = NSScrollView()
  private(set) var searchFocused = false
  var accentColor = Settings.defaultHighlightColor { didSet { refreshSearchPalette() } }
  let shortcutHint = NSTextField(labelWithString: "⌘F")

  let scrollView = NSScrollView()
  let gridView = CardGridView()
  let emptyLabel = NSTextField(labelWithString: "")
  let statusLabel = NSTextField(labelWithString: "")

  /// Placeholder is passive; the native editor exposes the actual accessible text value.
  static var searchPlaceholder: String { localized("Type to filter", "输入以过滤") }

  override var isFlipped: Bool { true }

  /// 手动布局的尺寸全部取自 GridLayout —— 面板整体尺寸（panelWidth /
  /// panelHeight）也是它算的，内容视图再自带一组 padding / headerHeight
  /// 就会把文档视图摆偏（同一份常量只能有一个来源）。
  private static let metrics = GridLayout(count: 0)
  private static let searchLeadingInset: CGFloat = 12
  private static let searchIconGap: CGFloat = 10

  init() {
    super.init(frame: .zero)

    // The logo sits outside the field; only the query and passive hint live inside.
    searchBox.wantsLayer = true
    searchBox.layer?.cornerRadius = 10
    if let url = Bundle.main.url(forResource: "slime", withExtension: "icns") {
      searchIcon.image = NSImage(contentsOf: url)
    }
    searchIcon.wantsLayer = true
    searchIcon.layer?.cornerRadius = 10
    searchIcon.layer?.masksToBounds = true
    searchIcon.setAccessibilityElement(false)
    searchIcon.imageScaling = .scaleProportionallyUpOrDown
    searchLabel.font = .systemFont(ofSize: 15)
    searchLabel.lineBreakMode = .byTruncatingTail
    setSearchText("")
    addSubview(searchIcon)
    shortcutHint.font = .systemFont(ofSize: 12, weight: .medium)
    shortcutHint.textColor = .labelColor
    shortcutHint.alignment = .center
    searchBox.addSubview(shortcutHint)
    searchClip.drawsBackground = false
    searchClip.hasHorizontalScroller = false
    searchClip.hasVerticalScroller = false
    searchClip.documentView = searchEditor
    searchClip.wantsLayer = true
    searchClip.layer?.masksToBounds = true
    searchBox.addSubview(searchClip)
    searchBox.addSubview(searchLabel)
    searchLabel.isSelectable = false
    searchEditor.onFocus = { [weak self] in self?.setSearchFocused(true) }

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
    refreshSearchPalette()
  }

  required init?(coder: NSCoder) { fatalError("面板只从代码建") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = superview.map { convert(point, from: $0) } ?? point
    if searchBox.frame.contains(local) { return searchEditor }
    return super.hitTest(point)
  }

  /// Programmatic text updates are only used before native editing takes ownership.
  func setSearchText(_ text: String) {
    searchEditor.setCommittedText(text)
    searchLabel.isHidden = !text.isEmpty || searchFocused
    let isEmpty = text.isEmpty
    searchLabel.stringValue = isEmpty ? Self.searchPlaceholder : text
    searchLabel.textColor = .labelColor
    searchBox.setAccessibilityValue(text)
    needsLayout = true
  }

  func setSearchFocused(_ focused: Bool) {
    guard focused != searchFocused else { return }
    searchFocused = focused
    refreshSearchPalette()
    updateShortcutVisibility()
    searchLabel.isHidden = focused || !searchEditor.string.isEmpty
    if focused {
      window?.makeFirstResponder(searchEditor)
      searchEditor.scrollRangeToVisible(searchEditor.selectedRange())
    } else if window?.firstResponder === searchEditor { window?.makeFirstResponder(nil) }
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  private func updateShortcutVisibility() {
    shortcutHint.isHidden = searchFocused || !statusLabel.stringValue.isEmpty
  }

  private func refreshSearchPalette() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let neutral = NSColor.labelColor
      searchBox.layer?.borderWidth = searchFocused ? 2 : 0
      searchBox.layer?.borderColor = accentColor.withAlphaComponent(0.85).cgColor
      searchBox.layer?.backgroundColor = (searchFocused
        ? accentColor.withAlphaComponent(0.10) : neutral.withAlphaComponent(0.06)).cgColor
      // A neutral edge keeps even a white custom accent visible on a light panel.
      let edge = NSShadow()
      edge.shadowColor = neutral.withAlphaComponent(0.65)
      edge.shadowBlurRadius = 1
      edge.shadowOffset = .zero
      searchBox.shadow = searchFocused ? edge : nil
      searchEditor.insertionPointColor = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? .white : .black
    }
  }

  func showStatus(_ message: String?) {
    statusLabel.stringValue = message ?? ""
    statusLabel.toolTip = message
    statusLabel.setAccessibilityLabel(message)
    updateShortcutVisibility()
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
    let previewInset = CardView.previewInset
    searchIcon.frame = NSRect(x: padding + previewInset, y: padding,
      width: searchHeight, height: searchHeight)
    let searchX = searchIcon.frame.maxX + Self.searchIconGap
    searchBox.frame = NSRect(x: searchX, y: padding,
      width: max(0, bounds.width - padding - previewInset - searchX), height: searchHeight)
    searchLabel.sizeToFit()
    let textX = Self.searchLeadingInset
    let hasStatus = !statusLabel.stringValue.isEmpty
    let trailingWidth: CGFloat = hasStatus ? searchBox.bounds.width * 0.50
      : (shortcutHint.isHidden ? 0 : 36)
    let available = max(0, searchBox.bounds.width - textX - Self.searchLeadingInset
      - trailingWidth - (trailingWidth > 0 ? 10 : 0))
    shortcutHint.sizeToFit()
    let hintHeight = shortcutHint.frame.height
    shortcutHint.frame = NSRect(x: searchBox.bounds.width - Self.searchLeadingInset - 36,
      y: (searchHeight - hintHeight) / 2, width: 36, height: hintHeight)
    searchLabel.frame = NSRect(x: textX, y: (searchHeight - searchLabel.frame.height) / 2,
      width: available, height: searchLabel.frame.height)
    searchClip.frame = NSRect(x: textX, y: (searchHeight - 22) / 2, width: available, height: 22)
    searchEditor.minSize = NSSize(width: available, height: 22)
    searchEditor.setFrameSize(NSSize(width: max(available, searchEditor.frame.width), height: 22))
    if let font = searchEditor.font, let manager = searchEditor.layoutManager {
      searchEditor.textContainerInset = NSSize(width: 0,
        height: max(0, (22 - manager.defaultLineHeight(for: font)) / 2))
    }

    statusLabel.frame = NSRect(x: searchBox.bounds.width - Self.searchLeadingInset - trailingWidth,
      y: (searchHeight - 16) / 2, width: trailingWidth, height: 16)
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
