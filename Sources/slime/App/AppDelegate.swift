import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var cache: WindowCache?
  private var panel: PanelController?
  private var eventTap: EventTap?
  private var statusItem: NSStatusItem?
  private let settings = Settings()
  private let settingsWindow = SettingsWindowController()
  private var lastEnabled = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    settingsWindow.onChange = { [weak self] in self?.settingsChanged() }
    installStatusItem()
    if settings.isEnabled { enable() }
  }

  private func settingsChanged() {
    installStatusItem()
    guard settings.isEnabled != lastEnabled else { return }
    if settings.isEnabled {
      enable()
    } else {
      lastEnabled = false
      panel?.dismiss()
      eventTap?.configure(enabled: false)
    }
  }

  private func enable() {
    guard Permission.isAccessibilityTrusted else {
      settings.isEnabled = false
      settingsWindow.refresh()
      Permission.promptAccessibility()
      Self.alert(localized("Accessibility access required", "需要辅助功能权限"),
        localized("Enable slime in System Settings → Privacy & Security → Accessibility, then restart slime.",
          "请在系统设置 → 隐私与安全性 → 辅助功能中开启 slime，然后重启 slime。"))
      return
    }
    if let eventTap {
      eventTap.configure(enabled: true)
      lastEnabled = true
      return
    }
    let cache = WindowCache()
    let panel = PanelController()
    let tap = EventTap(
      onEffects: { [weak panel] state, effects in panel?.handle(state: state, effects: effects) },
      onDegraded: { [weak self] in self?.tapDegraded() })
    do { try tap.start() } catch {
      settings.isEnabled = false
      settingsWindow.refresh()
      Self.alert(localized("Could not enable slime", "无法启用 slime"),
        localized("Keyboard monitoring could not start. Check Accessibility access and restart slime.",
          "无法启动键盘监听。请检查辅助功能权限并重启 slime。") + "\n\(error)")
      return
    }
    panel.onActivate = { [weak cache] window in
      WindowActivator.activate(window)
      cache?.noteActivated(window)
    }
    panel.onCancelSession = { [weak tap] in tap?.cancelSession() }
    panel.onCloseFinished = { [weak tap] in tap?.completeClose() }
    panel.onClosed = { [weak cache] window, siblings in cache?.noteClosed(window, preserving: siblings) }
    panel.onRefresh = { [weak cache] in cache?.refresh() }
    panel.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
    cache.onChange = { [weak cache, weak panel] windows in
      guard let cache else { return }
      AppIcons.warm(windows)
      WindowThumbnails.warm(cache.allWindows)
      panel?.setWindows(windows)
    }
    self.cache = cache
    self.panel = panel
    eventTap = tap
    lastEnabled = true
    cache.start()
    beginScreenRecordingOnboarding()
  }

  private func installStatusItem() {
    let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "slime")
    let menu = NSMenu()
    let settings = NSMenuItem(title: localized("Settings…", "设置…"), action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: localized("Quit slime", "退出 slime"), action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    item.menu = menu
    statusItem = item
  }

  @objc private func openSettings() { settingsWindow.show() }
  @objc private func quit() { NSApp.terminate(nil) }

  private func beginScreenRecordingOnboarding() {
    guard !Permission.hasScreenRecording else { return }
    let granted = Permission.requestScreenRecording()
    Self.alert(localized("Enable window previews", "开启窗口预览"),
      granted
        ? localized("Screen Recording access is enabled. Restart slime to load previews.", "屏幕录制权限已开启，请重启 slime 以加载预览。")
        : localized("You can switch windows without previews. To enable them, allow slime in System Settings → Privacy & Security → Screen Recording, then restart slime.",
          "没有预览也可以切换窗口。如需预览，请在系统设置 → 隐私与安全性 → 屏幕录制中允许 slime，然后重启 slime。"))
  }

  private func tapDegraded() {
    panel?.dismiss()
    settings.isEnabled = false
    lastEnabled = false
    settingsWindow.refresh()
    Self.alert(localized("slime stopped handling ⌘Tab", "slime 已停止接管 ⌘Tab"),
      localized("macOS repeatedly disabled keyboard monitoring. Native ⌘Tab is available. Check Accessibility access and restart slime.",
        "macOS 连续禁用了键盘监听，已恢复原生 ⌘Tab。请检查辅助功能权限并重启 slime。"))
  }

  private static func alert(_ title: String, _ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: localized("OK", "好"))
    alert.runModal()
  }
}
