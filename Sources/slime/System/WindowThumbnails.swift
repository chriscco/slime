import CoreGraphics
import ScreenCaptureKit

/// 窗口缩略图（spec §5）。三件事：按 windowID 缓存、后台抓取、按快照边界清理。
/// **不碰 AppKit 的视图** —— 视图那边只问它要一张图（`image(for:)`）。
///
/// 线程模型：缓存 / `pending` / `live` / `onChange` 全在主线程（`@MainActor`）；
/// 抓图是跨进程 IPC，**全在后台**（红线 4）—— 所以用 `Task.detached` 而不是
/// `Task {}`：后者从 MainActor 上下文继承隔离，等于把 IPC 放回主线程。
///
/// 抓的为什么不是私有 SkyLight 的 `CGSHWCaptureWindowList`（快 ~10ms，还能多抓
/// 一类 Chrome 窗口）：`dlopen` + 零文档 + 每次 macOS 升级赌一次，换 10ms 不值
/// （spec §4.2 / §5.1；CLAUDE.md 第一条第 4 级优先平台原生能力）。
@MainActor
enum WindowThumbnails {
  private static var cache: [UInt32: CGImage] = [:]
  /// 正在飞的窗口 —— 连续两次枚举之间不重复发 IPC。
  private static var pending: Set<UInt32> = []
  /// 当前快照里的窗口（`warm` 每次都重设）。
  private static var live: Set<UInt32> = []

  /// 有新图可显示时的回调（主线程）—— 面板就地把卡片刷新一遍。
  static var onChange: (() -> Void)?

  /// 缩略图的目标宽度（px）：卡片图区 160pt @2x。抓全分辨率是浪费 ——
  /// 一扇 1920×992 的 Chrome 在 2x 下是 30 MB。
  ///
  /// `nonisolated`：`shot(of:)` 是 nonisolated 的（红线 4），读不到 MainActor
  /// 隔离的存储属性 —— brief 原样（`private static let`）在 Swift 6.3 下报
  /// 「main actor-isolated static property cannot be accessed from outside」。
  private nonisolated static let targetPixelWidth = 320.0

  static func image(for window: Window) -> CGImage? { cache[window.windowID] }

  /// 让缓存对齐这份快照：丢掉不在快照里的、补抓还没有的。挂
  /// `WindowCache.onChange`，和 `AppIcons.warm` 同一个钩子 —— 用户第一次按下
  /// ⌘Tab 时缓存已经就绪（spec §5.3 要的「第一帧就是完整的」）。
  static func warm(_ windows: [Window]) {
    live = Set(windows.map(\.windowID))
    // 缓存按快照边界清理（spec §4.5）：窗口关掉就不会再显示 —— 没有任何东西
    // 在渲染它，缓存里也就不该留着。
    //
    // shortcut: 缩略图缓存只按 windowID 存，不做时间戳 / TTL —— 窗口关了就在
    //           快照边界清掉；真的出现过期图误导人时再加时效
    cache = cache.filter { live.contains($0.key) }

    let ids = windows.map(\.windowID).filter { cache[$0] == nil && !pending.contains($0) }
    guard !ids.isEmpty else { return }
    pending.formUnion(ids)

    // `Task.detached` 而不是 `Task {}`：后者在这个 @MainActor 的类型里会继承
    // 主 actor 隔离，抓图就回到主线程了（红线 4）。
    Task.detached(priority: .utility) {
      let captured = await Self.capture(ids)
      await MainActor.run { Self.publish(captured, ids: ids) }
    }
  }

  /// 抓取结束（主线程）：收进缓存。**只收还在快照里的** —— 快照换过之后，
  /// 上一批的窗口可能已经关了，塞回缓存就是「关掉的窗口还在显示」。
  private static func publish(_ captured: [UInt32: CGImage], ids: [UInt32]) {
    pending.subtract(ids)
    let fresh = captured.filter { live.contains($0.key) }
    guard !fresh.isEmpty else { return }
    for (id, image) in fresh { cache[id] = image }
    onChange?()
  }

  // MARK: - 后台（红线 4：这一节不碰主线程状态）

  /// 没权限 / 抓不到都返回空字典 —— 调用方只管「有没有图」。
  private nonisolated static func capture(_ ids: [UInt32]) async -> [UInt32: CGImage] {
    // 没权限就别白跑：每次枚举都去试一遍是无谓的 IPC，SCK 的报错还会刷满日志。
    // 这里用 CoreGraphics 直接问，不走 `App/Permission` —— `System/` 不许依赖
    // `App/`（CLAUDE.md 第六条）；而且对这一个模块它问的是「我能不能干活」，
    // 不是「要不要弹引导文案」（那个在 AppDelegate）。
    guard CGPreflightScreenCaptureAccess() else { return [:] }
    guard
      let content = try? await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
    else { return [:] }

    // 一次枚举只取一遍 SCShareableContent —— 每张都重取的话光这一步就是几百毫秒
    // （spec §13 那条待验证的风险）。
    let byID = Dictionary(
      content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

    return await withTaskGroup(of: (UInt32, CGImage)?.self) { group in
      for id in ids {
        guard let scWindow = byID[id] else { continue }
        // SCWindow 没标 Sendable（SDK 缺注解）：字段都是建好就不再变的只读快照，
        // 交给子任务只读，安全 —— 比 import 层面关掉整个框架的检查窄。
        nonisolated(unsafe) let window = scWindow
        group.addTask { await shot(of: window) }  // 并发抓：20 扇窗串行就是 400ms
      }
      var result: [UInt32: CGImage] = [:]
      for await pair in group {
        guard let (id, image) = pair, looksLikeWindowRender(image) else { continue }
        result[id] = image
      }
      return result
    }
  }

  /// 抓一扇窗。抓不到 / 不像窗口渲染都返回 nil（走缓存 → app 图标的降级）。
  private nonisolated static func shot(of scWindow: SCWindow) async -> (UInt32, CGImage)? {
    let frame = scWindow.frame
    guard frame.width > 0, frame.height > 0 else { return nil }
    let config = SCStreamConfiguration()
    config.width = Int(targetPixelWidth)
    config.height = max(1, Int(targetPixelWidth * frame.height / frame.width))
    config.showsCursor = false
    // 默认会把窗口的 shadow framing 一起抓进来（窗口因此从抓取边界内缩），
    // 关掉它，抓出来的图才是窗口本身 —— 圆角采样与长宽比都靠这条。
    // 实测（320pt 宽抓取）：默认抓图四角 alpha = 0（圆角外是空的）。
    config.ignoreShadowsSingleWindow = true

    // shortcut: 抓图走 SCK 公开 API，没用私有 SkyLight 的 CGSHWCaptureWindowList
    //           （它快 ~10ms 且能多抓一类 Chrome 窗口）—— 慢到感觉得出来时再说
    guard
      let image = try? await SCScreenshotManager.captureImage(
        contentFilter: SCContentFilter(desktopIndependentWindow: scWindow),
        configuration: config)
    else { return nil }
    return (scWindow.windowID, image)
  }

  /// 抓到的图是不是「像一扇真窗口」。台前调度搁置的窗口在合成层就被渲染成斜的
  /// 透视条带，有些直接是纯白（spec §4.1 实测）。这些图比 app 图标还难认 ——
  /// 丢掉它们，卡片退回缓存图或图标。判据只有两条，各对着一种实测坏法：
  ///
  /// 1. **四角都得不透明** —— 斜条带的四角落在窗口外，是空的。
  /// 2. **至少两种量化后的颜色** —— 「全白」「全黑」这种抓出来的空块只有一种。
  ///
  /// 先缩到 32×32 再采样：判据不该有性能代价。
  ///
  /// shortcut: 判据会误杀「整扇窗只有一个颜色」的窗口（全白的空文档）—— 那时
  ///           退回 app 图标，不是白屏。真的误导人时再细化（spec §14）
  nonisolated static func looksLikeWindowRender(_ image: CGImage) -> Bool {
    let side = 32
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    // 采样一律走 `buffer`（`bytes`），**不回头读 `pixels`** —— 那是对同一个
    // 数组的重复访问，Swift 的排他性检查会拦。
    return pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return true }  // 建不出上下文就别拦着：宁可显示一张图，不要白屏
      context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
      let bytes = buffer.bindMemory(to: UInt8.self)

      // 四角采样**内缩 2px**：真窗口的圆角本身就是透明的，采到最外圈的像素
      // 会把每一扇真窗口都判否。实测（320pt 宽抓图，32×32 采样）：
      //   (0,0) 的 alpha = 0（圆角外）→ 内缩 2px 后 = 255（不透明）。
      // 内缩不会放过「斜条带」——它的四角在 x ∈ [10, 22] 之外仍是空的。
      let corner = 2
      for (x, y) in [
        (corner, corner), (side - 1 - corner, corner),
        (corner, side - 1 - corner), (side - 1 - corner, side - 1 - corner),
      ] where bytes[(y * side + x) * 4 + 3] < 250 {
        return false
      }

      // 每通道取高 4 位做桶：抗抖动 / 抗压缩噪声，同时「纯色」还是只有一个桶。
      var seen: Set<UInt32> = []
      for index in stride(from: 0, to: bytes.count, by: 4) {
        let key =
          UInt32(bytes[index] >> 4) << 8 | UInt32(bytes[index + 1] >> 4) << 4
          | UInt32(bytes[index + 2] >> 4)
        seen.insert(key)
        if seen.count >= 2 { return true }
      }
      return false
    }
  }
}
