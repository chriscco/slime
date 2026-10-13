import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  var onChange: (() -> Void)?
  private let settings: Settings
  private var window: NSWindow?
  private var section = 0
  private let content = NSView()
  private let sidebar = NSStackView()
  private let body = NSStackView()
  private var loginSwitch: NSSwitch?
  private var loginStatus: NSTextField?
  private var loginBusy = false

  init(settings: Settings = Settings()) { self.settings = settings }

  func show() {
    let window = makeWindow()
    rebuild()
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  func refresh() { if window != nil { rebuild() } }

  func makeWindow() -> NSWindow {
    if let window { return window }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 510),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    self.window = window
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .windowBackgroundColor
    window.delegate = self
    window.contentView = content
    window.center()
    sidebar.orientation = .vertical
    sidebar.alignment = .leading
    sidebar.spacing = 6
    body.orientation = .vertical
    body.alignment = .leading
    body.spacing = 0
    let backdrop = NSView()
    backdrop.wantsLayer = true
    backdrop.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    for view in [backdrop, sidebar, body] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      backdrop.topAnchor.constraint(equalTo: content.topAnchor),
      backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      backdrop.widthAnchor.constraint(equalToConstant: 174),
      sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      sidebar.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -12),
      sidebar.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
      body.leadingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: 28),
      body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
      body.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
    ])
    rebuild()
    return window
  }

  func windowDidBecomeKey(_ notification: Notification) { syncLoginStatus() }

  private func text(_ english: String, _ chinese: String) -> String { settings.text(english, chinese) }

  private func rebuild() {
    window?.title = text("slime Settings", "slime 设置")
    for stack in [sidebar, body] {
      for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
    }
    loginSwitch = nil; loginStatus = nil
    let names = [text("General", "通用"), text("Appearance", "外观"),
      text("Shortcuts", "快捷键"), text("About", "关于")]
    let symbols = ["switch.2", "paintpalette", "keyboard", "info.circle"]
    for (index, name) in names.enumerated() {
      let button = NSButton(title: name, target: self, action: #selector(selectSection(_:)))
      button.tag = index
      button.isBordered = false
      let item = NSView()
      item.wantsLayer = true
      item.layer?.cornerRadius = 8
      item.layer?.backgroundColor = (section == index
        ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .clear).cgColor
      button.font = .systemFont(ofSize: 13, weight: section == index ? .semibold : .regular)
      button.contentTintColor = section == index ? .controlAccentColor : .secondaryLabelColor
      button.setButtonType(.pushOnPushOff)
      button.state = section == index ? .on : .off
      button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)
      button.imagePosition = .imageLeading
      button.alignment = .left
      button.translatesAutoresizingMaskIntoConstraints = false
      item.addSubview(button)
      sidebar.addArrangedSubview(item)
      NSLayoutConstraint.activate([
        item.widthAnchor.constraint(equalTo: sidebar.widthAnchor),
        item.heightAnchor.constraint(equalToConstant: 36),
        button.leadingAnchor.constraint(equalTo: item.leadingAnchor, constant: 12),
        button.trailingAnchor.constraint(equalTo: item.trailingAnchor, constant: -12),
        button.topAnchor.constraint(equalTo: item.topAnchor),
        button.bottomAnchor.constraint(equalTo: item.bottomAnchor),
      ])
    }
    if section != 3 {
      let heading = label(names[section], size: 24, weight: .semibold)
      body.addArrangedSubview(heading)
      body.setCustomSpacing(24, after: heading)
    }
    switch section {
    case 0: general()
    case 1: appearance()
    case 2: shortcuts()
    default: about()
    }
  }

  private func general() {
    row(text("Enable slime", "启用 slime"), detail: text(
      "Turn off to use the system window switcher.", "关闭后使用系统原生切换器。"),
      control: toggle(settings.isEnabled, action: #selector(enabledChanged(_:))))
    row(text("Group windows by app", "按应用分组"), detail: text(
      "Give each app its own section.", "每个应用单独一组，另起一行。"),
      control: toggle(settings.groupByApp, action: #selector(groupChanged(_:))))
    let login = toggle(SMAppService.mainApp.status == .enabled, action: #selector(loginChanged(_:)))
    loginSwitch = login
    row(text("Launch at login", "登录时启动"), detail: text(
      "Ready when you sign in.", "登录后自动启动。"), control: login)
    let status = label("", size: 11, secondary: true)
    loginStatus = status
    body.addArrangedSubview(status)
    let manage = NSButton(title: text("Manage Login Items…", "管理登录项…"),
      target: self, action: #selector(openLoginItems))
    manage.bezelStyle = .inline
    body.addArrangedSubview(manage)
    body.setCustomSpacing(8, after: manage)
    let language = NSPopUpButton()
    language.addItems(withTitles: ["English", "简体中文"])
    language.selectItem(at: settings.language == .english ? 0 : 1)
    language.target = self; language.action = #selector(languageChanged(_:))
    row(text("Language", "语言"), detail: text("Applies throughout slime.", "立即应用到 slime 的所有界面。"),
      control: language)
    syncLoginStatus()
  }

  private func appearance() {
    let style = NSSegmentedControl(labels: [text("Regular", "标准"), text("Clear", "通透")],
      trackingMode: .selectOne, target: self, action: #selector(styleChanged(_:)))
    style.selectedSegment = settings.glassStyle == .regular ? 0 : 1
    row(text("Glass style", "玻璃样式"), control: style)
    let strength = NSSlider(value: settings.glassStrength, minValue: 0, maxValue: 1,
      target: self, action: #selector(strengthChanged(_:)))
    row(text("Glass strength", "玻璃强度"), detail: text("Opaque to transparent", "从不透明到透明"), control: strength)
    let color = NSColorWell()
    color.colorWellStyle = .minimal; color.color = settings.highlightColor
    color.target = self; color.action = #selector(colorChanged(_:))
    row(text("Accent color", "高亮颜色"), detail: text("Selection tint and underline", "选中底色与下划线"), control: color)
    let radius = NSSlider(value: settings.glassCornerRadius, minValue: 0, maxValue: 40,
      target: self, action: #selector(radiusChanged(_:)))
    row(text("Panel corners", "面板圆角"), detail: text("Square to rounded", "从直角到圆角"), control: radius)
    let note = label(text("Changes appear the next time you open the switcher.", "下次打开切换面板时显示更改。"), size: 11, secondary: true)
    body.addArrangedSubview(note)
  }

  private func shortcuts() {
    let entries = [
      (text("Quick switch · release to confirm", "快速切换 · 松手确认"), "⌘ Tab"),
      (text("Open and keep the switcher", "打开并保留面板"), "⌥ Tab"),
      (text("Next / previous window", "后一个 / 前一个窗口"), "Tab / ⇧ Tab"),
      (text("Navigate windows / rows", "按窗口 / 按行导航"), "← → / ↑ ↓"),
      (text("Filter / delete a character", "过滤 / 删除字符"), text("Type / ⌫", "键入 / ⌫")),
      (text("Keep open and search", "保留面板并搜索"), "⌘ F / ⌥ F"),
      (text("Switch to selection", "切到选中窗口"), "↵"),
      (text("Close selected window", "关闭选中窗口"), "⌘ D"),
      (text("Open settings", "打开设置"), "⌘ , / ⌥ ,"),
      (text("Cancel", "取消"), "Esc"),
    ]
    for (title, keys) in entries {
      let keyLabel = label(keys, size: 12, weight: .medium)
      keyLabel.alignment = .right
      row(title, control: keyLabel, height: 33)
    }
  }

  private func about() {
    let name = label("slime", size: 36, weight: .semibold)
    body.addArrangedSubview(name)
    body.setCustomSpacing(10, after: name)
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? text("Development", "开发版")
    let versionLabel = label(text("Version ", "版本 ") + version, size: 13, secondary: true)
    body.addArrangedSubview(versionLabel)
    body.setCustomSpacing(22, after: versionLabel)
    let github = NSButton(title: text("View on GitHub ↗", "在 GitHub 查看 ↗"), target: self, action: #selector(openGitHub))
    github.isBordered = false
    github.contentTintColor = .linkColor
    body.addArrangedSubview(github)
  }

  private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                     secondary: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = secondary ? .secondaryLabelColor : .labelColor
    return label
  }

  private func toggle(_ value: Bool, action: Selector) -> NSSwitch {
    let control = NSSwitch()
    control.state = value ? .on : .off
    control.target = self; control.action = action
    return control
  }

  private func row(_ title: String, detail: String? = nil, control: NSView, height: CGFloat = 66) {
    let line = NSView()
    let titleLabel = label(title)
    for view in [titleLabel, control] { view.translatesAutoresizingMaskIntoConstraints = false; line.addSubview(view) }
    body.addArrangedSubview(line)
    line.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    line.heightAnchor.constraint(equalToConstant: height).isActive = true
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: line.leadingAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: line.centerYAnchor, constant: detail == nil ? 0 : -9),
      control.trailingAnchor.constraint(equalTo: line.trailingAnchor),
      control.centerYAnchor.constraint(equalTo: line.centerYAnchor),
      control.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
    ])
    if let control = control as? NSControl { control.setAccessibilityLabel(title) }
    if let detail {
      let description = label(detail, size: 11, secondary: true)
      description.translatesAutoresizingMaskIntoConstraints = false
      line.addSubview(description)
      NSLayoutConstraint.activate([
        description.leadingAnchor.constraint(equalTo: line.leadingAnchor),
        description.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        description.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -8),
      ])
    }
  }

  private func syncLoginStatus() {
    let status = SMAppService.mainApp.status
    loginSwitch?.state = status == .enabled ? .on : .off
    loginSwitch?.isEnabled = !loginBusy
    switch status {
    case .enabled: loginStatus?.stringValue = text("Enabled in macOS.", "已在 macOS 中启用。")
    case .requiresApproval: loginStatus?.stringValue = text("Allow slime in System Settings → Login Items.", "请在系统设置 → 登录项中允许 slime。")
    case .notFound: loginStatus?.stringValue = text("macOS could not locate slime. Open the installed app and try again.", "macOS 找不到 slime，请打开安装好的应用再试。")
    case .notRegistered: loginStatus?.stringValue = ""
    @unknown default: loginStatus?.stringValue = text("Check Login Items in System Settings.", "请检查系统设置中的登录项。")
    }
  }

  @objc private func selectSection(_ sender: NSButton) { section = sender.tag; rebuild() }
  @objc private func enabledChanged(_ sender: NSSwitch) { settings.isEnabled = sender.state == .on; onChange?() }
  @objc private func groupChanged(_ sender: NSSwitch) { settings.groupByApp = sender.state == .on; onChange?() }
  @objc private func languageChanged(_ sender: NSPopUpButton) {
    settings.language = sender.indexOfSelectedItem == 1 ? .chinese : .english
    rebuild(); onChange?()
  }
  @objc private func styleChanged(_ sender: NSSegmentedControl) {
    settings.glassStyle = sender.selectedSegment == 0 ? .regular : .clear; onChange?()
  }
  @objc private func strengthChanged(_ sender: NSSlider) { settings.glassStrength = sender.doubleValue; onChange?() }
  @objc private func radiusChanged(_ sender: NSSlider) { settings.glassCornerRadius = sender.doubleValue; onChange?() }
  @objc private func colorChanged(_ sender: NSColorWell) { settings.highlightColor = sender.color; onChange?() }
  @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/chriscco/slime")!) }
  @objc private func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
  @objc private func loginChanged(_ sender: NSSwitch) {
    guard !loginBusy else { return }
    let enable = sender.state == .on
    loginBusy = true; sender.isEnabled = false
    Task { @MainActor in
      do {
        if enable {
          if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
          else { try SMAppService.mainApp.register() }
        } else { try await SMAppService.mainApp.unregister() }
        loginBusy = false; syncLoginStatus()
      } catch {
        loginBusy = false; syncLoginStatus()
        let alert = NSAlert()
        alert.messageText = text("Could not change login setting", "无法更改登录设置")
        alert.informativeText = text("macOS returned: ", "macOS 返回：") + error.localizedDescription
        alert.addButton(withTitle: text("OK", "好"))
        if let window { await alert.beginSheetModal(for: window) }
      }
    }
  }
}
