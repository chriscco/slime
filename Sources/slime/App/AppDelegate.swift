import AppKit

/// 组装（spec §7 启动流程）：权限 → 事件 tap → 缓存 → 面板。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var cache: WindowCache?
  private var panel: PanelController?
  private var eventTap: EventTap?
  private var statusItem: NSStatusItem?
  private let settingsWindow = SettingsWindowController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard Permission.isAccessibilityTrusted else {
      Self.beginPermissionOnboarding()
      return
    }
    start()
    // 屏幕录制走另一条路：没它也能用，所以只弹一次文案，不拦启动、不退出。
    Self.beginScreenRecordingOnboarding()
  }

  // MARK: - 启动

  private func start() {
    let cache = WindowCache()
    let panel = PanelController()

    let tap = EventTap(
      onEffects: { [weak panel] state, effects in
        panel?.handle(state: state, effects: effects)
      },
      onDegraded: { [weak self] in self?.tapDegraded() }
    )
    do {
      try tap.start()
    } catch {
      // spec §9：事件 tap 建不起来就报错退出，不要静默地留在后台。
      Self.alert(
        "slime 启动失败",
        "事件监听装不上（\(error)）。常见原因是辅助功能权限没生效 —— 授权后需要重启 slime。")
      NSApp.terminate(nil)
      return
    }

    panel.onActivate = { [weak cache] window in
      WindowActivator.activate(window)
      cache?.noteActivated(window)
    }
    panel.onRefresh = { [weak cache] in cache?.refresh() }
    panel.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
    // 图标与缩略图的预热挂在这里：onChange 在 MainActor.assumeIsolated 里触发，
    // 天然在主线程。`WindowThumbnails.warm` 只是把后台抓取发出去 —— 首次唤出
    // 面板时缓存已经就绪（除了「启动后 100ms 内就按 ⌘Tab」那种情况，那时先显示
    // 图标、抓完由 onChange 就地换成缩略图）。
    cache.onChange = { [weak panel] windows in
      AppIcons.warm(windows)
      WindowThumbnails.warm(windows)
      panel?.setWindows(windows)
    }

    self.cache = cache
    self.panel = panel
    self.eventTap = tap

    installStatusItem()
    cache.start()  // 首次枚举 + 订阅 didActivateApplication（维护 MRU）
  }

  // MARK: - 菜单栏

  /// 菜单栏图标（spec §8）。app 是 .accessory，没有 Dock 图标也没有菜单栏项 ——
  /// 不加这个，设置页做出来打不开。
  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "slime")

    let menu = NSMenu()
    let settings = NSMenuItem(
      title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "退出 slime", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    item.menu = menu

    statusItem = item
  }

  @objc private func openSettings() {
    settingsWindow.show()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  // MARK: - 权限

  /// 没权限：弹系统对话框引导；用户授权后提示重启（授权对运行中的进程不生效）。
  private static func beginPermissionOnboarding() {
    Permission.promptAccessibility()
    Permission.waitUntilTrusted { trusted in
      let message =
        trusted
        ? "辅助功能权限已开启。请重启 slime —— 权限只对新启动的进程生效。"
        : "没等到辅助功能权限。请在「系统设置 → 隐私与安全性 → 辅助功能」里勾上 slime，然后重新打开它。"
      alert("slime 需要辅助功能权限", message)
      NSApp.terminate(nil)
    }
  }

  /// 屏幕录制（spec §6）。**不退出、不拦启动** —— 没权限时 slime 照常切换窗口，
  /// 只是卡片显示 app 图标。跟辅助功能那条引导的唯一区别就在这。
  private static func beginScreenRecordingOnboarding() {
    guard !Permission.hasScreenRecording else { return }
    let granted = Permission.requestScreenRecording()
    alert(
      "开启窗口缩略图",
      granted
        ? "屏幕录制权限已开启。请重启 slime —— 权限只对新启动的进程生效。"
        : """
          没给屏幕录制权限也能正常切换窗口，只是卡片会显示 app 图标，而不是窗口缩略图。

          想要缩略图：在「系统设置 → 隐私与安全性 → 屏幕录制」里勾上 slime，然后重启它。
          """)
  }

  /// tap 连续被系统禁掉（红线 3 的兜底已在 EventTap 生效）——
  /// 这时多半也是权限被撤销（spec §9「权限中途被撤销」），顺手再引导一次。
  private func tapDegraded() {
    let trusted = Permission.isAccessibilityTrusted
    if !trusted { Permission.promptAccessibility() }
    Self.alert(
      "slime 已停止接管 ⌘+Tab",
      trusted
        ? "系统连续禁用了 slime 的事件监听，已退回系统原生 ⌘+Tab。重启 slime 可以再试。"
        : "辅助功能权限被关掉了。在系统设置里重新开启，然后重启 slime。")
  }

  private static func alert(_ title: String, _ message: String) {
    NSApp.activate()  // accessory app 的弹窗要在前台才看得见
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "好")
    alert.runModal()
  }
}
