import AppKit

/// app 图标，按 bundle id 缓存。
///
/// 取图标是主线程 API（`NSWorkspace`），而枚举在后台线程（红线 4）。所以启动时
/// 那次枚举完成后先预热一遍（`AppIcons.warm`，从 `WindowCache.onChange` 调，
/// 那里天然在主线程），快捷键路径上只读缓存、一次都不取。
///
/// `@MainActor` 是必需的，不是装饰：`NSWorkspace` / `NSRunningApplication`
/// 都是主线程 API，而这份缓存也是可变全局状态。
@MainActor
enum AppIcons {
  private static var cache: [String: NSImage] = [:]

  /// 取不到时的兜底。SF Symbol 一定存在，不会返回 nil。
  private static let fallback: NSImage = {
    let image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
    return image ?? NSImage(size: NSSize(width: 64, height: 64))
  }()

  /// 预热：把快照里每个 app 的图标先取一遍。
  static func warm(_ windows: [Window]) {
    for window in windows { _ = icon(for: window) }
  }

  static func icon(for window: Window) -> NSImage? {
    guard let key = cacheKey(for: window.pid) else { return fallback }
    if let hit = cache[key] { return hit }
    guard
      let app = NSRunningApplication(processIdentifier: window.pid),
      let url = app.bundleURL
    else { return fallback }
    // shortcut: 缓存只增不删 —— 上限是「这台机器上见过多少个 app」，几十个量级。
    //           变成问题时按 pid 消失回收。
    let image = NSWorkspace.shared.icon(forFile: url.path)
    cache[key] = image
    return image
  }

  /// bundle id 优先（同一 app 的多个窗口共用一张图标）；拿不到就退回 bundle 路径。
  private static func cacheKey(for pid: pid_t) -> String? {
    guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
    return app.bundleIdentifier ?? app.bundleURL?.path
  }
}
