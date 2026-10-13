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
  private var closingID: UInt32?
  private let highlight = HighlightView()
  private var cards: [CardView] = []
  private var headings: [NSView] = []
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
      card.setSelected(i == selection && rows[i].windowID != closingID, color: highlightColor, animated: motion)
    }
    guard !rows.isEmpty, let layer = highlight.layer else { return }
    let cell = cardRect(selection)
    let target = NSRect(x: cell.midX - 16, y: cell.maxY - 7, width: 32, height: 4)
    if previous == selection, highlight.frame == target,
       layer.animation(forKey: "selection") != nil,
       !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
    let oldFrame = layer.presentation()?.frame ?? highlight.frame
    layer.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlight.frame = target
    CATransaction.commit()
    guard motion, previous != selection else { return }
    if layout.shouldAnimate(from: previous, to: selection), abs(oldFrame.midY - target.midY) < 1 {
      let bulge = min(max(0, 52 - oldFrame.width),
                      min(20, abs(target.midX - oldFrame.midX) * 0.08))
      let samples = (0...32).map { step -> (width: CGFloat, position: NSValue) in
        let t = CGFloat(step) / 32
        let travel = 1 - pow(1 - t, 3)
        let settle = t * t * (3 - 2 * t)
        let width = oldFrame.width + (target.width - oldFrame.width) * settle
          + bulge * pow(sin(.pi * t), 2)
        let center = oldFrame.midX + (target.midX - oldFrame.midX) * travel
        return (width, NSValue(point: NSPoint(
          x: center + (layer.anchorPoint.x - 0.5) * width,
          y: target.minY + layer.anchorPoint.y * target.height)))
      }
      let slide = CAKeyframeAnimation(keyPath: "position")
      slide.values = samples.map(\.position)
      let stretch = CAKeyframeAnimation(keyPath: "bounds.size.width")
      stretch.values = samples.map(\.width)
      // One continuous travel curve; width has zero slope at its peak and ends.
      for animation in [slide, stretch] { animation.duration = 0.3 }
      let motion = CAAnimationGroup()
      motion.animations = [slide, stretch]
      motion.duration = 0.3
      layer.add(motion, forKey: "selection")

    }
  }

  func setClosing(_ id: UInt32?) {
    closingID = id
    let motion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    for (index, card) in cards.enumerated() {
      let closing = rows[index].windowID == id
      card.setSelected(index == selection && !closing, color: highlightColor, animated: motion)
      card.setTitleVisible(!closing, animated: motion)
    }
    Self.fade(highlight, to: id == nil ? 1 : 0, animated: motion)
  }

  static func fade(_ view: NSView, to alpha: CGFloat, animated: Bool) {
    let previous = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
    view.alphaValue = alpha
    view.layer?.removeAnimation(forKey: "closeFade")
    if animated {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = previous; fade.toValue = alpha; fade.duration = 0.1
      view.layer?.add(fade, forKey: "closeFade")
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
  private var thumbnail: CGImage?
  private var displayedWindow: Window?
  override var isFlipped: Bool { true }

  init(window: Window) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 14
    label.wantsLayer = true
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
    let image = WindowThumbnails.image(for: window)
    let changed = thumbnail !== image
    if changed {
      thumbnail = image
      preview.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
    guard changed || displayedWindow != window else { return }
    displayedWindow = window
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

  func setTitleVisible(_ visible: Bool, animated: Bool) {
    CardGridView.fade(label, to: visible ? 1 : 0, animated: animated)
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
  var image: NSImage? { didSet { if oldValue !== image { needsDisplay = true } } }
  var appIcon: NSImage? { didSet { if oldValue !== appIcon { needsDisplay = true } } }
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
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let duration = reduced ? 0.12 : 0.56
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    parent.addSublayer(overlay)
    closingOverlay = overlay
    layer?.opacity = 0
    if reduced {
      overlay.contents = bitmap.cgImage
      overlay.opacity = 0
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 1; fade.toValue = 0; fade.duration = duration
      overlay.add(fade, forKey: "crt")
    } else {
      // Keep the luminous line and dot independent of the shrinking bitmap:
      // scaling the whole composition also flattens its glow into a hard rectangle.
      func track(_ path: String, _ values: [CGFloat], _ times: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = times
        animation.timingFunctions = (1..<values.count).map { _ in
          CAMediaTimingFunction(name: .easeInEaseOut)
        }
        return animation
      }
      func animate(_ target: CALayer, _ animations: [CAAnimation]) {
        target.opacity = 0
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        target.add(group, forKey: "crt")
      }
      let picture = CALayer()
      picture.frame = overlay.bounds
      picture.contents = bitmap.cgImage
      overlay.addSublayer(picture)
      animate(picture, [
        track("transform.scale.y", [1, 1.015, 0.035, 0.008, 0.008], [0, 0.08, 0.36, 0.44, 1]),
        track("transform.scale.x", [1, 1.025, 1.025], [0, 0.36, 1]),
        track("opacity", [1, 1, 0.8, 0, 0], [0, 0.28, 0.4, 0.46, 1]),
      ])
      let exposure = CALayer()
      exposure.frame = picture.bounds
      exposure.backgroundColor = NSColor.white.cgColor
      let mask = CALayer()
      mask.frame = exposure.bounds
      mask.contents = bitmap.cgImage
      exposure.mask = mask
      picture.addSublayer(exposure)
      let flash = track("opacity", [0, 0.08, 0.85, 1, 0], [0, 0.12, 0.36, 0.44, 1])
      flash.duration = duration
      exposure.opacity = 0
      exposure.add(flash, forKey: "exposure")

      let imageWidth = image.map { Self.imageRect(size: $0.size, in: bounds).width } ?? bounds.width
      let beam = CALayer()
      beam.bounds = CGRect(x: 0, y: 0, width: imageWidth, height: 2)
      beam.position = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
      beam.cornerRadius = 1
      beam.backgroundColor = NSColor.white.cgColor
      beam.shadowColor = NSColor(calibratedRed: 0.65, green: 0.86, blue: 1, alpha: 1).cgColor
      beam.shadowOffset = .zero
      beam.shadowRadius = 6
      beam.shadowOpacity = 0.95
      overlay.addSublayer(beam)
      animate(beam, [
        track("bounds.size.width", [imageWidth, imageWidth, 4, 2], [0, 0.44, 0.76, 1]),
        track("opacity", [0, 0, 1, 1, 0, 0], [0, 0.28, 0.4, 0.64, 0.8, 1]),
      ])

      let dot = CALayer()
      dot.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
      dot.position = beam.position
      dot.cornerRadius = 2
      dot.backgroundColor = NSColor.white.cgColor
      dot.shadowColor = beam.shadowColor
      dot.shadowOffset = .zero
      dot.shadowRadius = 9
      dot.shadowOpacity = 1
      overlay.addSublayer(dot)
      animate(dot, [
        track("opacity", [0, 0, 1, 0.45, 0.7, 0], [0, 0.7, 0.77, 0.85, 0.91, 1]),
        track("transform.scale", [1, 1, 1.3, 0.2], [0, 0.75, 0.84, 1]),
      ])
    }
    CATransaction.commit()
    try? await Task.sleep(for: .seconds(duration))
    overlay.removeFromSuperlayer()
    if closingOverlay === overlay { closingOverlay = nil }
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
    layer?.cornerRadius = 2
    layer?.backgroundColor = color.cgColor
    isHidden = true
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }
}
