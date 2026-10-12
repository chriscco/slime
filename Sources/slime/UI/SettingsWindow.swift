import AppKit

/// 设置窗口（spec §8）。三个控件，就这三样。
///
/// 从 `.accessory` app 打开普通窗口必须先 `NSApp.activate()`，
/// 否则窗口会开在别的 app 后面，用户以为没反应。
@MainActor
final class SettingsWindowController {
  private var settings = Settings()
  private var window: NSWindow?

  private let styleControl = NSSegmentedControl(
    labels: ["标准", "通透"], trackingMode: .selectOne, target: nil, action: nil)
  private let tintWell = NSColorWell()
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
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 190),
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
      [label("色调"), tintWell],
      [label("圆角"), radiusSlider],
    ])
    grid.rowSpacing = 12
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .trailing
    grid.frame = NSRect(x: 20, y: 20, width: 280, height: 130)

    styleControl.target = self
    styleControl.action = #selector(styleChanged)
    styleControl.selectedSegment = 0

    tintWell.target = self
    tintWell.action = #selector(tintChanged)
    tintWell.colorWellStyle = .minimal

    radiusSlider.target = self
    radiusSlider.action = #selector(radiusChanged)
    radiusSlider.isContinuous = true

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 190))
    container.addSubview(grid)
    return container
  }

  private func label(_ text: String) -> NSTextField {
    NSTextField(labelWithString: text)
  }

  /// 窗口每次打开都从 settings 同步一次 —— settings 是唯一真相。
  private func syncControlsFromSettings() {
    styleControl.selectedSegment = settings.glassStyle == .regular ? 0 : 1
    if let tint = settings.glassTint { tintWell.color = tint }
    radiusSlider.doubleValue = settings.glassCornerRadius
  }

  @objc private func styleChanged() {
    settings.glassStyle = styleControl.selectedSegment == 0 ? .regular : .clear
  }

  @objc private func tintChanged() {
    // 「无色调」用滑块的极端位置表达不了，所以色板取到白就算清除。
    // shortcut: 没有显式的「无色调」按钮 —— 真嫌不够用时再加一个复选框。
    settings.glassTint = tintWell.color == .white ? nil : tintWell.color
  }

  @objc private func radiusChanged() {
    settings.glassCornerRadius = radiusSlider.doubleValue
  }
}
