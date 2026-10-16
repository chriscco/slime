import AppKit

/// Static opaque illustrations, deliberately independent of live window capture and glass.
final class PanelBackgroundButton: NSButton {
  let theme: Settings.PanelBackground

  init(theme: Settings.PanelBackground, title: String, target: AnyObject, action: Selector) {
    self.theme = theme
    super.init(frame: .zero)
    self.title = title
    self.target = target
    self.action = action
    // Use a full-rectangle cell hit region; draw(_:) supplies the custom appearance.
    setButtonType(.pushOnPushOff)
    bezelStyle = .shadowlessSquare
    isBordered = true
    focusRingType = .exterior
    setAccessibilityElement(true)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel(title)
  }

  required init?(coder: NSCoder) { fatalError("Use init(theme:title:target:action:)") }

  override func accessibilityValue() -> Any? { state.rawValue }

  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9).fill()
  }

  override func draw(_ dirtyRect: NSRect) {
    let outer = bounds.insetBy(dx: 2, dy: 2)
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: outer, xRadius: 9, yRadius: 9).fill()
    let preview = NSRect(x: 10, y: 10, width: max(0, bounds.width - 20), height: max(0, bounds.height - 40))
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: preview, xRadius: 6, yRadius: 6).addClip()
    if theme == .system {
      drawPanel(in: NSRect(x: preview.minX, y: preview.minY, width: preview.width / 2, height: preview.height), theme: .white)
      drawPanel(in: NSRect(x: preview.midX, y: preview.minY, width: preview.width / 2, height: preview.height), theme: .black)
    } else { drawPanel(in: preview, theme: theme) }
    NSGraphicsContext.restoreGraphicsState()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
    (title as NSString).draw(at: NSPoint(x: 12, y: bounds.height - 24), withAttributes: attributes)
    if state == .on {
      ("✓" as NSString).draw(at: NSPoint(x: bounds.width - 25, y: bounds.height - 24), withAttributes: attributes)
      NSColor.labelColor.withAlphaComponent(0.7).setStroke()
      let border = NSBezierPath(roundedRect: outer, xRadius: 9, yRadius: 9)
      border.lineWidth = 2
      border.stroke()
    }
  }

  private func drawPanel(in rect: NSRect, theme: Settings.PanelBackground) {
    theme.baseColor(systemIsDark: false).setFill()
    rect.fill()
    let ink: NSColor = theme == .white ? .black : .white
    ink.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + 7, y: rect.minY + 7,
      width: max(0, rect.width - 14), height: 10), xRadius: 3, yRadius: 3).fill()
    let gap: CGFloat = 5
    let width = max(0, (rect.width - 14 - 2 * gap) / 3)
    for index in 0..<3 {
      let card = NSRect(x: rect.minX + 7 + CGFloat(index) * (width + gap),
        y: rect.minY + 24, width: width, height: max(0, rect.height - 32))
      ink.withAlphaComponent(0.20).setFill()
      NSBezierPath(roundedRect: card, xRadius: 3, yRadius: 3).fill()
    }
  }
}
