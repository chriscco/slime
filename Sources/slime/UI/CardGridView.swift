import AppKit

/// Cards are reused by window identity; only the underline travels between cells.
final class CardGridView: NSView {
  var rows: [Window] = [] {
    didSet {
      if rows.map(\.windowID) == oldValue.map(\.windowID) {
        for (window, card) in zip(rows, cards) { card.update(window: window) }
        return
      }
      var pool = Dictionary(uniqueKeysWithValues: zip(oldValue, cards).map { ($0.windowID, $1) })
      cards = rows.map { window in
        let card = pool.removeValue(forKey: window.windowID) ?? CardView(window: window)
        card.update(window: window)
        if card.superview == nil { addSubview(card) }
        return card
      }
      for card in pool.values { card.removeFromSuperview() }
      addSubview(highlight, positioned: .above, relativeTo: nil)
      updateLayout()
    }
  }
  var groupByApp = false { didSet { if groupByApp != oldValue { updateLayout() } } }
  var availableWidth: Double? { didSet { if availableWidth != oldValue { updateLayout() } } }
  private(set) var layout = GridLayout(count: 0)
  private(set) var selection = 0
  var highlightColor: NSColor = Settings.defaultHighlightColor {
    didSet { highlight.color = highlightColor; setSelection(selection, animated: false) }
  }
  private let highlight = HighlightView()
  private var cards: [CardView] = []
  private var headings: [NSView] = []
  private var departingUnderline: CALayer?
  private var contentWidth: CGFloat = 0
  override var isFlipped: Bool { true }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    addSubview(highlight)
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  func setContentWidth(_ width: CGFloat) {
    guard contentWidth != width else { return }
    contentWidth = width
    applyLayout()
  }

  func setSelection(_ index: Int, animated: Bool) {
    let previous = selection
    selection = min(max(0, index), max(0, rows.count - 1))
    highlight.isHidden = rows.isEmpty
    let motion = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    for (i, card) in cards.enumerated() {
      card.setSelected(i == selection, color: highlightColor, animated: motion)
    }
    guard !rows.isEmpty, let layer = highlight.layer else { return }
    let cell = cardRect(selection)
    let target = NSRect(x: cell.midX - 16, y: cell.maxY - 7, width: 32, height: 3)
    let oldFrame = layer.presentation()?.frame ?? highlight.frame
    departingUnderline?.removeFromSuperlayer()
    departingUnderline = nil
    layer.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlight.frame = target
    CATransaction.commit()
    guard motion, previous != selection else { return }
    if layout.shouldAnimate(from: previous, to: selection) {
      let slide = CABasicAnimation(keyPath: "position")
      slide.fromValue = NSValue(point: NSPoint(
        x: oldFrame.minX + layer.anchorPoint.x * oldFrame.width,
        y: oldFrame.minY + layer.anchorPoint.y * oldFrame.height))
      slide.toValue = NSValue(point: layer.position)
      slide.duration = 0.18
      slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
      layer.add(slide, forKey: "selection")
    } else {
      let old = CALayer()
      old.frame = oldFrame
      old.cornerRadius = 1.5
      old.backgroundColor = highlightColor.cgColor
      self.layer?.addSublayer(old)
      departingUnderline = old
      let out = CABasicAnimation(keyPath: "opacity")
      out.fromValue = 1; out.toValue = 0; out.duration = 0.12
      old.opacity = 0
      old.add(out, forKey: "out")
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.12
      layer.add(fade, forKey: "selection")
    }
  }

  func scrollSelectionToVisible() {
    guard rows.indices.contains(selection) else { return }
    scrollToVisible(cardRect(selection))
  }

  func card(for id: UInt32) -> CardView? {
    guard let index = rows.firstIndex(where: { $0.windowID == id }) else { return nil }
    return cards[index]
  }

  private func cardRect(_ index: Int) -> NSRect {
    let point = layout.origin(of: index)
    return NSRect(x: point.x, y: point.y, width: layout.cardWidth, height: layout.cardHeight)
  }

  private func updateLayout() {
    let starts = groupByApp ? rows.indices.filter { $0 == 0 || rows[$0].pid != rows[$0 - 1].pid } : []
    layout = GridLayout(count: rows.count, groupStarts: starts, availableWidth: availableWidth)
    for heading in headings { heading.removeFromSuperview() }
    headings = starts.map { index in
      let heading = NSView()
      let icon = NSImageView(image: AppIcons.icon(for: rows[index]) ?? NSImage())
      icon.frame = NSRect(x: 4, y: 6, width: 16, height: 16)
      icon.imageScaling = .scaleProportionallyDown
      let title = NSTextField(labelWithString: rows[index].appName)
      title.font = .systemFont(ofSize: 12, weight: .medium)
      title.textColor = .secondaryLabelColor
      title.frame = NSRect(x: 27, y: 6, width: layout.gridWidth - 31, height: 17)
      heading.addSubview(icon); heading.addSubview(title)
      let y = layout.origin(of: index).y - GridLayout.groupHeaderHeight
      heading.frame = NSRect(x: 0, y: y, width: layout.gridWidth, height: 28)
      addSubview(heading)
      return heading
    }
    applyLayout()
    setSelection(selection, animated: false)
  }

  private func applyLayout() {
    for (i, card) in cards.enumerated() { card.frame = cardRect(i) }
    frame.size = NSSize(width: contentWidth > 0 ? contentWidth : layout.gridWidth,
      height: layout.contentHeight)
    setSelection(selection, animated: false)
  }
}

final class CardView: NSView {
  let preview = WindowPreviewView()
  private let label = NSTextField(labelWithString: "")
  override var isFlipped: Bool { true }

  init(window: Window) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 14
    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    addSubview(preview); addSubview(label)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    update(window: window)
  }
  required init?(coder: NSCoder) { fatalError("Use init(window:)") }

  func update(window: Window) {
    preview.image = WindowThumbnails.image(for: window)
      .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    preview.appIcon = AppIcons.icon(for: window)
    let unavailable = localized("Preview unavailable", "无法获取预览")
    preview.toolTip = preview.image == nil ? unavailable : nil
    label.stringValue = window.title.isEmpty ? window.appName : window.title
    toolTip = window.label
    setAccessibilityLabel(window.label)
    setAccessibilityHelp(preview.image == nil ? unavailable : nil)
  }

  func setSelected(_ selected: Bool, color: NSColor, animated: Bool) {
    setAccessibilityValue(selected ? localized("Selected", "已选中") : "")
    guard let layer else { return }
    let target = selected ? color.withAlphaComponent(0.13).cgColor : NSColor.clear.cgColor
    guard layer.backgroundColor != target else { return }
    let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
    CATransaction.begin(); CATransaction.setDisableActions(true)
    layer.backgroundColor = target
    CATransaction.commit()
    layer.removeAnimation(forKey: "tint")
    if animated {
      let fade = CABasicAnimation(keyPath: "backgroundColor")
      fade.fromValue = previous; fade.toValue = target; fade.duration = 0.16
      layer.add(fade, forKey: "tint")
    }
  }

  override func layout() {
    super.layout()
    preview.frame = NSRect(x: 8, y: 8, width: max(0, bounds.width - 16),
      height: max(0, bounds.height - 45))
    label.frame = NSRect(x: 6, y: bounds.height - 30,
      width: max(0, bounds.width - 12), height: 17)
  }
}

/// Draws the actual aspect-fit image through a rounded path, including portrait images.
final class WindowPreviewView: NSView {
  var image: NSImage? { didSet { needsDisplay = true } }
  var appIcon: NSImage? { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }
  override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
  convenience init() { self.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  private var closingOverlay: CALayer?

  func restore() {
    closingOverlay?.removeFromSuperlayer()
    closingOverlay = nil
    layer?.opacity = 1
  }

  func animateClose() async {
    guard let parent = superview?.layer,
          let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return }
    cacheDisplay(in: bounds, to: bitmap)
    let overlay = CALayer()
    overlay.frame = frame
    overlay.contents = bitmap.cgImage
    parent.addSublayer(overlay)
    closingOverlay = overlay
    layer?.opacity = 0
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let duration = reduced ? 0.12 : 0.45
    let opacity = CAKeyframeAnimation(keyPath: "opacity")
    opacity.values = reduced ? [1, 0] : [1, 1, 1, 0.2, 1, 0]
    opacity.keyTimes = reduced ? [0, 1] : [0, 0.44, 0.78, 0.85, 0.91, 1]
    var animations: [CAAnimation] = [opacity]
    if !reduced {
      let vertical = CAKeyframeAnimation(keyPath: "transform.scale.y")
      vertical.values = [1, 0.018, 0.018, 0.018]
      vertical.keyTimes = [0, 0.44, 0.78, 1]
      let horizontal = CAKeyframeAnimation(keyPath: "transform.scale.x")
      horizontal.values = [1, 1, 0.014, 0.014]
      horizontal.keyTimes = [0, 0.44, 0.78, 1]
      animations += [vertical, horizontal]
      let glow = CALayer()
      glow.frame = overlay.bounds
      glow.backgroundColor = NSColor.white.cgColor
      overlay.addSublayer(glow)
      let brighten = CABasicAnimation(keyPath: "opacity")
      brighten.fromValue = 0; brighten.toValue = 1; brighten.duration = duration * 0.44
      glow.add(brighten, forKey: "brighten")
    }
    let group = CAAnimationGroup()
    group.animations = animations
    group.duration = duration
    group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    overlay.opacity = 0
    overlay.add(group, forKey: "crt")
    try? await Task.sleep(for: .seconds(duration))
    overlay.removeFromSuperlayer()
  }

  static func imageRect(size: NSSize, in bounds: NSRect) -> NSRect {
    guard size.width > 0, size.height > 0 else { return bounds }
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let width = size.width * scale, height = size.height * scale
    return NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
      width: width, height: height)
  }

  override func draw(_ dirtyRect: NSRect) {
    let rect = image.map { Self.imageRect(size: $0.size, in: bounds) } ?? bounds
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).addClip()
    if let image {
      image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: nil)
    } else {
      NSColor.controlBackgroundColor.setFill(); rect.fill()
      NSColor.labelColor.withAlphaComponent(0.08).setFill()
      NSRect(x: 0, y: 0, width: bounds.width, height: 18).fill()
      NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
      for x in [8.0, 15.0, 22.0] {
        NSBezierPath(ovalIn: NSRect(x: x, y: 7, width: 4, height: 4)).fill()
      }
      NSColor.labelColor.withAlphaComponent(0.09).setFill()
      for (i, fraction) in [0.62, 0.8, 0.48].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 12, y: 31 + Double(i) * 10,
          width: max(0, (bounds.width - 24) * fraction), height: 4), xRadius: 2, yRadius: 2).fill()
      }
      let side = min(36, max(0, bounds.height - 28))
      let icon = appIcon?.withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor])) ?? appIcon
      icon?.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2 + 6,
        width: side, height: side), from: .zero, operation: .sourceOver,
        fraction: 1, respectFlipped: true, hints: nil)
    }
    NSGraphicsContext.restoreGraphicsState()
  }
}

final class HighlightView: NSView {
  var color: NSColor = Settings.defaultHighlightColor {
    didSet { layer?.backgroundColor = color.cgColor }
  }
  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 1.5
    layer?.backgroundColor = color.cgColor
    isHidden = true
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }
}
