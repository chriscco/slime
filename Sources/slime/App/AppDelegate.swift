import AppKit

/// 组装（spec §7 启动流程）：权限 → 事件 tap → 缓存 → 面板。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var cache: WindowCache?
  private var panel: PanelController?
  private var eventTap: EventTap?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard Permission.isAccessibilityTrusted else {
      Self.beginPermissionOnboarding()
      return
    }
    start()
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
    cache.onChange = { [weak panel] windows in panel?.setWindows(windows) }

    self.cache = cache
    self.panel = panel
    self.eventTap = tap

    cache.start()  // 首次枚举 + 订阅 didActivateApplication（维护 MRU）
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
