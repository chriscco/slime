import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillTerminate(_ notification: Notification) {
    activationRequest?.cancel()
    cache?.stop()
  }

  private var cache: WindowCache?
  private var activationRequest: AXRequest?
  private var panel: PanelController?
  private var eventTap: EventTap?
  private var statusItem: NSStatusItem?
  private let settings: Settings
  private let updater = AppUpdater()
  private lazy var settingsWindow: SettingsWindowController = {
    let controller = SettingsWindowController(settings: settings, updater: updater)
    controller.isRunning = { [weak self] in self?.lastEnabled ?? false }
    controller.onChange = { [weak self] in self?.settingsChanged() }
    controller.onEnabledChange = { [weak self] in self?.enabledChanged() }
    return controller
  }()
  private var lastEnabled = false

  init(settings: Settings = Settings()) {
    self.settings = settings
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    WindowThumbnails.configure(source: settings.previewSource)
    installStatusItem()
    updater.start()
    if settings.isEnabled { enable() }
  }

  private func settingsChanged() {
    if WindowThumbnails.configure(source: settings.previewSource), let cache {
      WindowThumbnails.warm(cache.allWindows)
    }
    panel?.refreshAppearance()
    installStatusItem()
  }

  private func enabledChanged() {
    guard settings.isEnabled != lastEnabled else { return }
    if settings.isEnabled {
      enable()
    } else {
      lastEnabled = false
      activationRequest?.cancel()
      cache?.stop()
      panel?.dismiss()
      eventTap?.configure(enabled: false)
    }
  }

  func enable(
    isAccessibilityTrusted: () -> Bool = { Permission.isAccessibilityTrusted },
    promptAccessibility: () -> Void = { Permission.promptAccessibility() }
  ) {
    guard isAccessibilityTrusted() else {
      settingsWindow.hideForPermissionPrompt()
      promptAccessibility()
      return
    }
    if let eventTap {
      eventTap.configure(enabled: true)
      cache?.start()
      lastEnabled = true
      return
    }
    let cache = WindowCache()
    let panel = PanelController()
    let tap = EventTap(
      onEffects: { [weak self, weak panel] state, effects in
        for effect in effects {
          if case .showPanel = effect { self?.activationRequest?.cancel() }
        }
        panel?.handle(state: state, effects: effects)
      },
      onDegraded: { [weak self] in self?.tapDegraded() })
    do { try tap.start() } catch {
      settings.isEnabled = false
      settingsWindow.refresh()
      Self.alert(localized("Could not enable slime", "无法启用 slime"),
        localized("Keyboard monitoring could not start. Check Accessibility access and restart slime.",
          "无法启动键盘监听。请检查辅助功能权限并重启 slime。") + "\n\(error)")
      return
    }
    panel.onActivate = { [weak self, weak cache] window in
      self?.activationRequest?.cancel()
      let request = AXRequest(seconds: 0.15)
      self?.activationRequest = request
      let target = cache?.targets[window.windowID]
      Task {
        let result = await WindowActivator.activate(window, target: target, request: request)
        if result == .exact { cache?.noteActivated(window) }
      }
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
    settingsWindow.hideForPermissionPrompt()
    let granted = Permission.requestScreenRecording()
    Self.alert(localized("Enable window previews", "开启窗口预览"),
      granted
        ? localized("Screen Recording access is enabled. Restart slime to load previews.", "屏幕录制权限已开启，请重启 slime 以加载预览。")
        : localized("You can switch windows without previews. To enable them, allow slime in System Settings → Privacy & Security → Screen Recording, then restart slime.",
          "没有预览也可以切换窗口。如需预览，请在系统设置 → 隐私与安全性 → 屏幕录制中允许 slime，然后重启 slime。"))
  }

  private func tapDegraded() {
    activationRequest?.cancel()
    cache?.stop()
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
