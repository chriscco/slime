import AppKit

/// 设置窗口（spec §8）。四个控件：玻璃样式 / 强度 / 高亮色 / 圆角。
///
/// 从 `.accessory` app 打开普通窗口必须先 `NSApp.activate()`，
/// 否则窗口会开在别的 app 后面，用户以为没反应。
@MainActor
final class SettingsWindowController {
  private var settings = Settings()
  private var window: NSWindow?

  private let styleControl = NSSegmentedControl(
    labels: ["标准", "通透"], trackingMode: .selectOne, target: nil, action: nil)
  private let strengthSlider = NSSlider(
    value: Settings.defaultGlassStrength,
    minValue: Settings.strengthRange.lowerBound,
    maxValue: Settings.strengthRange.upperBound,
    target: nil, action: nil)
  private let highlightWell = NSColorWell()
  private let radiusSlider = NSSlider(
    value: Settings.defaultCornerRadius,
    minValue: Settings.cornerRadiusRange.lowerBound,
    maxValue: Settings.cornerRadiusRange.upperBound,
    target: nil, action: nil)

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    syncControlsFromSettings()
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 210),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "slime 设置"
    window.isReleasedWhenClosed = false
    window.contentView = makeContentView()
    window.center()
    return window
  }

  private func makeContentView() -> NSView {
    let grid = NSGridView(views: [
      [label("玻璃样式"), styleControl],
      [label("玻璃强度"), strengthSlider],
      [label("高亮颜色"), highlightWell],
      [label("圆角"), radiusSlider],
    ])
    grid.rowSpacing = 12
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .trailing
    grid.frame = NSRect(x: 20, y: 20, width: 280, height: 170)

    styleControl.target = self
    styleControl.action = #selector(styleChanged)
    styleControl.selectedSegment = 0

    strengthSlider.target = self
    strengthSlider.action = #selector(strengthChanged)
    strengthSlider.isContinuous = true

    highlightWell.target = self
    highlightWell.action = #selector(highlightChanged)
    highlightWell.colorWellStyle = .minimal

    radiusSlider.target = self
    radiusSlider.action = #selector(radiusChanged)
    radiusSlider.isContinuous = true

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 210))
    container.addSubview(grid)
    return container
  }

  private func label(_ text: String) -> NSTextField {
    NSTextField(labelWithString: text)
  }

  /// 窗口每次打开都从 settings 同步一次 —— settings 是唯一真相。
  private func syncControlsFromSettings() {
    styleControl.selectedSegment = settings.glassStyle == .regular ? 0 : 1
    strengthSlider.doubleValue = settings.glassStrength
    highlightWell.color = settings.highlightColor
    radiusSlider.doubleValue = settings.glassCornerRadius
  }

  @objc private func styleChanged() {
    settings.glassStyle = styleControl.selectedSegment == 0 ? .regular : .clear
  }

  @objc private func strengthChanged() {
    settings.glassStrength = strengthSlider.doubleValue
  }

  @objc private func highlightChanged() {
    settings.highlightColor = highlightWell.color
  }

  @objc private func radiusChanged() {
    settings.glassCornerRadius = radiusSlider.doubleValue
  }
}
