import CoreGraphics
import ScreenCaptureKit

/// Cached previews retain good renders; fresh previews live only for one panel session.
/// Both use background screenshots and identity tickets; previews arrive after presentation.
/// **不碰 AppKit 的视图** —— 视图那边只问它要一张图（`image(for:)`）。
///
/// 线程模型：缓存 / `pending` / `live` / `onChange` 全在主线程（`@MainActor`）；
/// 抓图是跨进程 IPC，**全在后台**（红线 4）—— 所以用 `Task.detached` 而不是
/// `Task {}`：后者从 MainActor 上下文继承隔离，等于把 IPC 放回主线程。
///
/// **有一半窗口抓不到**（用户实测的现象：面板里大部分卡片只有 app 图标）：
/// 其他 Space、最小化、台前调度搁置的窗口在合成层没有被渲染，SCK 对它们要么报
/// `-3811 音频/视频捕捉失败`、要么给斜条带 / 全白（spec §4.1）。这不是节流、
/// 也不是并发引起的 —— 串行抓、隔 6 秒重试，失败的还是同一批。所以：
///
/// - 图**落盘**（Application Support/slime/thumbs，按 windowID）：窗口在**当前
///   Space 出现过的那一次**抓到真图，之后长时间显示那一张 —— 正是 spec §4.5 的
///   「缓存上一张好图 → app 图标」降级链。平台自己也这么做：系统给最小化窗口
///   显示的就是它上一次的样子。
/// - 抓不到的窗口**记进负缓存**（`unrenderable`），不在每次枚举里重试 ——
///   避免对仍然离屏的失败窗口反复发起无效 IPC。
/// - **在屏**的窗口每次枚举都刷新（可见 → 抓得到 → 内容会变）；刷新不阻塞首帧。
///   所以缓存里那张图是「它在屏时的最近一次」。
///
/// 抓的为什么不是私有 SkyLight 的 `CGSHWCaptureWindowList`（快 ~10ms，还能多抓
/// 一类 Chrome 窗口）：`dlopen` + 零文档 + 每次 macOS 升级赌一次，换 10ms 不值
/// （spec §4.2 / §5.1；CLAUDE.md 第一条第 4 级优先平台原生能力）。
@MainActor
enum WindowThumbnails {
  private static var cache: [UInt32: CGImage] = [:]
  /// 正在飞的**必备**图（内存里还没有图的窗口）—— 连续两次枚举之间不重复发 IPC。
  /// 面板立即展示占位图，不等待这一批完成。
  private static var pending: Set<UInt32> = []
  /// 正在飞的**刷新**图（有图、窗口在屏上）。不阻塞首帧：结果回来就地换卡片。
  private static var refreshing: Set<UInt32> = []
  /// 当前快照里的窗口（`warm` 每次都重设）。
  private static var live: Set<UInt32> = []
  private static var prunedIDs: Set<UInt32>?
  private static var owners: [UInt32: pid_t] = [:]
  private static var tickets: [UInt32: UUID] = [:]
  private static var diskChecked: Set<UInt32> = []
  /// 负缓存：抓过、失败了、**而且当时不在屏上**的窗口 —— 本来就没渲染，重试
  /// 多少次都一样。等它真的在屏上（或关掉）时 `warm` 把条目清掉，再抓。
  private static var unrenderable: Set<UInt32> = []

  private static var source: Settings.PreviewSource = .cached
  private static var sessionOpen = false
  private static var attempted: [UInt32: Bool] = [:]
  private static var imageTasks: [UUID: Task<[UInt32: CGImage], Never>] = [:]
  private static let diskQueue = ThumbnailDiskQueue()
  private static var diskTasks: [UUID: Task<Void, Never>] = [:]

  @discardableResult
  static func configure(source newSource: Settings.PreviewSource) -> Bool {
    guard source != newSource else { return false }
    source = newSource
    resetImages()
    for task in diskTasks.values { task.cancel() }
    diskTasks.removeAll()
    onChange?()
    return true
  }

  static func beginSession(source: Settings.PreviewSource) {
    configure(source: source)
    sessionOpen = true
    if source == .fresh { resetImages(); onChange?() }
  }

  static func endSession() {
    sessionOpen = false
    if source == .fresh { resetImages() }
  }

  private static func resetImages() {
    for task in imageTasks.values { task.cancel() }
    imageTasks.removeAll()
    cache.removeAll(); tickets.removeAll(); pending.removeAll(); refreshing.removeAll()
    diskChecked.removeAll(); unrenderable.removeAll(); attempted.removeAll()
    whenSettledCallback = nil
    prunedIDs = nil
  }

  /// Cancellation prevents queued work; a filesystem operation already started may finish.
  private static func onDisk(writing ids: Set<UInt32> = [], _ body: @escaping @Sendable () -> Void) {
    let id = UUID()
    let queue = diskQueue
    diskTasks[id] = Task.detached(priority: .utility) {
      await queue.perform(body)
      await diskFinished(id, writtenIDs: ids)
    }
  }

  private static func diskFinished(_ id: UUID, writtenIDs: Set<UInt32>) {
    diskTasks.removeValue(forKey: id)
    // Detached saves can reach the disk queue after a newer snapshot's prune.
    if !writtenIDs.isSubset(of: live) { prunedIDs = nil }
  }

  /// 有新图可显示时的回调（主线程）—— 面板就地把卡片刷新一遍。
  static var onChange: (() -> Void)?

  /// Pending windows without a usable image; presentation no longer waits for them.
  static var hasPendingWork: Bool { pending.contains { cache[$0] == nil } }

  private static var whenSettledCallback: (() -> Void)?

  /// 这一批（`pending`，没图的）抓完 —— 成或败都算 —— 时在主线程调一次。
  /// 没有在飞的批次时立刻调：语义是「现在这批的结果已经定了」。
  static func whenSettled(_ body: @escaping () -> Void) {
    guard hasPendingWork else {
      body()
      return
    }
    whenSettledCallback = body
  }

  private static func notifySettledIfIdle() {
    guard !hasPendingWork, let callback = whenSettledCallback else { return }
    whenSettledCallback = nil
    callback()
  }

  /// 缩略图的目标宽度（px）：卡片图区 240pt @2x 上下。抓全分辨率是浪费 ——
  /// 一扇 1920×992 的 Chrome 在 2x 下是 30 MB。
  ///
  /// `nonisolated`：`shot(of:)` 是 nonisolated 的（红线 4），读不到 MainActor
  /// 隔离的存储属性 —— brief 原样（`private static let`）在 Swift 6.3 下报
  /// 「main actor-isolated static property cannot be accessed from outside」。
  private nonisolated static let targetPixelWidth = 320.0

  // MARK: - 落盘

  /// 缩略图落盘目录。为什么要落盘见文件头：其他 Space 的窗口抓不到，只能靠
  /// 「见过一次」的那张图，而它必须**跨 slime 重启存活** —— 不存的话用户看到的
  /// 就是「大部分窗口只有 app 图标」。
  ///
  /// `nonisolated`：`save` / `load` / `pruneDisk` 都在后台跑（红线 4）。
  private nonisolated static let thumbsDirectory: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("slime/thumbs", isDirectory: true)
  }()

  private nonisolated static func thumbURL(_ windowID: UInt32) -> URL {
    thumbsDirectory.appendingPathComponent("\(windowID).png")
  }

  /// 用 PNG：无损、系统自带编解码（`CGImageDestination`），一扇窗 20–40 KB。
  ///
  /// shortcut: 每次抓到都重写一遍（一次 app 切换 ≈ 4 扇在屏窗）—— 真嫌费盘时
  ///           再加「变了才写」的脏检查
  private nonisolated static func save(_ windowID: UInt32, _ image: CGImage) {
    // 目标目录可能不在（首次运行 / 用户清过 Application Support）。
    try? FileManager.default.createDirectory(
      at: thumbsDirectory, withIntermediateDirectories: true)
    guard
      let destination = CGImageDestinationCreateWithURL(
        thumbURL(windowID) as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
  }

  private nonisolated static func load(_ windowID: UInt32) -> CGImage? {
    guard
      let data = try? Data(contentsOf: thumbURL(windowID)),
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0,
      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
  }

  /// 清盘上不在这一轮快照里的图 —— 与内存同一条规则（spec §4.5：关掉的窗口
  /// 不会被任何东西渲染）。关掉的窗口不在这份快照里（known 表在枚举里自然
  /// 修剪），所以「见过一次」的图不会被误删，关掉的那个会被删。
  private nonisolated static func pruneDisk(keeping survivors: Set<UInt32>) {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: thumbsDirectory, includingPropertiesForKeys: nil)) ?? []
    for file in files {
      guard !Task.isCancelled else { return }
      guard let id = UInt32(file.deletingPathExtension().lastPathComponent) else { continue }
      if survivors.contains(id) { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  // MARK: - 主线程

  static func image(for window: Window) -> CGImage? { cache[window.windowID] }

  /// 让缓存对齐这份快照：丢掉不在快照里的、从盘上补进已有的、补抓还没有的。
  /// Warm from WindowCache.onRefreshPreviews; the panel does not wait for completion.
  static func warm(_ windows: [Window],
    diskLoader: @escaping @Sendable ([UInt32]) async -> [UInt32: CGImage] = { await loadDiskImages($0) },
    captureImages: (@Sendable ([UInt32], @escaping @MainActor @Sendable ([UInt32: CGImage]) -> Void) async -> [UInt32: CGImage])? = nil,
    pruneImages: @escaping @Sendable (Set<UInt32>) -> Void = { pruneDisk(keeping: $0) },
    saveImages: @escaping @Sendable ([UInt32: CGImage]) -> Void = { images in
      for (id, image) in images where !Task.isCancelled { save(id, image) }
    }) {
    guard source == .cached || sessionOpen else { return }
    let requestSource = source
    live = Set(windows.map(\.windowID))
    tickets = tickets.filter { live.contains($0.key) }
    attempted = attempted.filter { live.contains($0.key) }
    diskChecked.formIntersection(live)
    pending.formIntersection(live)
    refreshing.formIntersection(live)
    for window in windows where tickets[window.windowID] == nil || owners[window.windowID] != window.pid {
      tickets[window.windowID] = UUID()
      cache.removeValue(forKey: window.windowID)
      diskChecked.remove(window.windowID)
      pending.remove(window.windowID)
      refreshing.remove(window.windowID)
      unrenderable.remove(window.windowID)
      attempted.removeValue(forKey: window.windowID)
    }
    owners = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0.pid) })
    // 缓存按快照边界清理（spec §4.5）：窗口关掉就不会再显示 —— 没有任何东西
    // 在渲染它，缓存里也就不该留着。
    //
    // shortcut: 缩略图缓存只按 windowID 存，不做时间戳 / TTL —— 窗口关了就在
    //           快照边界清掉；真的出现过期图误导人时再加时效
    cache = cache.filter { live.contains($0.key) }
    // 关掉的窗口的负缓存条目也清掉（id 会被 WindowServer 复用）。
    unrenderable.formIntersection(live)

    let survivors = live
    if source == .cached, prunedIDs != survivors {
      prunedIDs = survivors
      onDisk { pruneImages(survivors) }
    }

    let plan = source == .fresh ? (needed: windows.filter { window in
      let previous = attempted[window.windowID]
      return previous == nil || (previous == false && window.isOnscreen && cache[window.windowID] == nil
        && !pending.contains(window.windowID))
    }.map(\.windowID), refresh: [UInt32]()) : Self.capturePlan(
      windows: windows,
      cached: Set(cache.keys),
      busy: pending.union(refreshing),
      unrenderable: unrenderable
    )
    guard !plan.needed.isEmpty || !plan.refresh.isEmpty else { return }
    if source == .fresh {
      let needed = Set(plan.needed)
      for window in windows where needed.contains(window.windowID) { attempted[window.windowID] = window.isOnscreen }
    }
    pending.formUnion(plan.needed)
    refreshing.formUnion(plan.refresh)

    let readIDs = source == .cached ? plan.needed.filter { !diskChecked.contains($0) } : []
    diskChecked.formUnion(readIDs)
    let expected = tickets
    let onscreen = Set(windows.filter(\.isOnscreen).map(\.windowID))
    Task {
      guard (plan.needed + plan.refresh).contains(where: { tickets[$0] == expected[$0] }) else {
        notifySettledIfIdle()
        return
      }
      var loaded: [UInt32: CGImage] = [:]
      let currentReadIDs = readIDs.filter { tickets[$0] == expected[$0] }
      if requestSource == .cached && !currentReadIDs.isEmpty {
        let loadID = UUID()
        let task = Task.detached(priority: .utility) { await diskLoader(currentReadIDs) }
        imageTasks[loadID] = task
        loaded = await task.value
        imageTasks.removeValue(forKey: loadID)
      }
      publishDisk(loaded, expected: expected)
      let ids = (plan.needed.filter { loaded[$0] == nil || onscreen.contains($0) } + plan.refresh)
        .filter { tickets[$0] == expected[$0] }
      guard !ids.isEmpty else {
        Self.publish([:], needed: plan.needed, refresh: plan.refresh, expected: expected)
        return
      }
      let captureID = UUID()
      let task = Task.detached(priority: .utility) {
        let progress: @MainActor @Sendable ([UInt32: CGImage]) -> Void = { images in
          publishImages(images, expected: expected)
        }
        if let captureImages { return await captureImages(ids, progress) }
        return await capture(ids, source: requestSource, progress: progress)
      }
      imageTasks[captureID] = task
      let captured = await task.value
      imageTasks.removeValue(forKey: captureID)
      let accepted = captured.filter { tickets[$0.key] == expected[$0.key] }
      if requestSource == .cached && !accepted.isEmpty { persist(accepted, saveImages: saveImages) }
      Self.publish(accepted, needed: plan.needed, refresh: plan.refresh, expected: expected)
    }
  }

  static func persist(_ images: [UInt32: CGImage], saveImages: @escaping @Sendable ([UInt32: CGImage]) -> Void) {
    onDisk(writing: Set(images.keys)) { saveImages(images) }
  }

  static func loadDiskImages(_ ids: [UInt32],
    loader: @escaping @Sendable (UInt32) -> CGImage? = { load($0) }) async -> [UInt32: CGImage] {
    let task = Task.detached(priority: .utility) {
      var images: [UInt32: CGImage] = [:]
      for id in ids {
        guard !Task.isCancelled else { break }
        if let image = loader(id) { images[id] = image }
      }
      return images
    }
    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private static func publishDisk(_ images: [UInt32: CGImage], expected: [UInt32: UUID]) {
    var changed = false
    for (id, image) in images where tickets[id] == expected[id] && cache[id] == nil {
      cache[id] = image
      changed = true
    }
    if changed { onChange?() }
    notifySettledIfIdle()
  }

  /// 纯函数：这一轮要抓哪些窗口（`WindowThumbnailsTests` 直接测）。两类结果的
  /// 区别只在**听不听结果**：
  ///
  /// - `needed`：内存里还没有图，先显示占位图，随后就地填入。
  ///   负缓存里的**只在它不在屏上时**跳过 —— 抓过、失败了、当时没渲染（其他
  ///   Space / 最小化），现在也一样；等它真的在屏上就该再给一次机会（那时它
  ///   是能抓的）。
  /// - `refresh`：有图、但窗口**在屏上** —— 可见窗口的内容会变，图得跟得上。
  ///   不在屏上的不刷：抓不到（-3811 或坏图），只会白烧 IPC 并反复往负缓存
  ///   记账。缓存里那张图因此是「它在屏时的最近一次」。
  ///
  /// 正在飞的不重复发（`busy` = `pending` ∪ `refreshing`）。
  nonisolated static func capturePlan(
    windows: [Window], cached: Set<UInt32>, busy: Set<UInt32>, unrenderable: Set<UInt32>
  ) -> (needed: [UInt32], refresh: [UInt32]) {
    var needed: [UInt32] = []
    var refresh: [UInt32] = []
    for window in windows {
      let id = window.windowID
      guard !busy.contains(id) else { continue }
      if cached.contains(id) {
        if window.isOnscreen { refresh.append(id) }
      } else if window.isOnscreen || !unrenderable.contains(id) {
        needed.append(id)
      }
    }
    return (needed, refresh)
  }

  /// 抓取结束（主线程）：收进缓存。**只收还在快照里的** —— 快照换过之后，
  /// 上一批的窗口可能已经关了，塞回缓存就是「关掉的窗口还在显示」。
  private static func publish(
    _ captured: [UInt32: CGImage], needed: [UInt32], refresh: [UInt32], expected: [UInt32: UUID]
  ) {
    let currentNeeded = needed.filter { tickets[$0] == expected[$0] }
    pending.subtract(currentNeeded)
    refreshing.subtract(refresh.filter { tickets[$0] == expected[$0] })
    for id in currentNeeded where captured[id] == nil && cache[id] == nil { unrenderable.insert(id) }
    publishImages(captured, expected: expected)
    notifySettledIfIdle()
  }

  private static func publishImages(_ images: [UInt32: CGImage], expected: [UInt32: UUID]) {
    var changed = false
    for (id, image) in images where tickets[id] == expected[id] && expected[id] != nil {
      if cache[id] !== image { cache[id] = image; changed = true }
    }
    if changed { onChange?() }
  }

  // MARK: - 后台（红线 4：这一节不碰主线程状态）

  /// 没权限 / 抓不到都返回空字典 —— 调用方只管「有没有图」。
  private nonisolated static func capture(_ ids: [UInt32], source: Settings.PreviewSource,
    progress: @escaping @MainActor @Sendable ([UInt32: CGImage]) -> Void) async -> [UInt32: CGImage] {
    guard !ids.isEmpty else { return [:] }
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

    // **串行**抓。为什么不用并发：实测离屏窗口的失败与并发无关（并发被抓一批时
    // 失败的那几个，串行重试、隔 6 秒再试，还是同一批）；而终端里对 79 个真实
    // 窗口顺序抓是 16–25ms/个、稳定成功。20 扇窗串行约 400ms，全在后台（红线 4）。
    //
    // Publish each completed capture without waiting for slower windows.
    // Keep serial capture until bounded concurrency is validated separately.
    var result: [UInt32: CGImage] = [:]
    for id in ids {
      guard !Task.isCancelled else { break }
      guard let scWindow = byID[id] else { continue }
      guard
        let (capturedID, image) = await shot(of: scWindow),
        looksLikeWindowRender(image, source: source)
      else { continue }
      result[capturedID] = image
      await progress([capturedID: image])
    }
    return result
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
  nonisolated static func looksLikeWindowRender(_ image: CGImage, source: Settings.PreviewSource = .cached) -> Bool {
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
      ] where source == .cached && bytes[(y * side + x) * 4 + 3] < 250 {
        return false
      }

      // 每通道取高 4 位做桶：抗抖动 / 抗压缩噪声，同时「纯色」还是只有一个桶。
      var seen: Set<UInt32> = []
      for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] >= 250 {
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


/// Serialize PNG writes/pruning without making the main actor wait for filesystem work.
private actor ThumbnailDiskQueue {
  func perform(_ body: @Sendable () -> Void) {
    guard !Task.isCancelled else { return }
    body()
  }
}
