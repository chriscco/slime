import CoreGraphics
import Foundation
import Testing

@testable import slime

// 「抓到的图像不像一扇真窗口」这个判据的测试（spec §16 选的是方案 (a)：
// 全抓 + 丢弃不像窗口的结果）。图全部是合成出来的 —— 不依赖屏幕录制权限，
// 也不依赖真窗口，所以能进 CI。

/// 画一张 64×64 的图。新 CGContext 是清零的 = 全透明黑，正好是
/// 「抓空了」和「斜条带的四角」两种坏法的底。
private func image(_ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  draw(context)
  return context.makeImage()!
}

private func opaque(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
  CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension PanelAndThumbnailTests {
@Test func anEmptyImageIsNotAWindowRender() {
  // 抓空的极端情形：整张全透明。
  #expect(!WindowThumbnails.looksLikeWindowRender(image { _ in }))
}
}

extension PanelAndThumbnailTests {
@Test func aSolidImageIsNotAWindowRender() {
  // spec §4.1 实测的坏法之一：台前调度搁置的窗口抓出来是**全白**的。
  // 它比 app 图标还难认，必须丢掉。
  #expect(
    !WindowThumbnails.looksLikeWindowRender(
      image { context in
        context.setFillColor(opaque(1, 1, 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
      }))
}
}

extension PanelAndThumbnailTests {
@Test func anImageWithEmptyCornersIsNotAWindowRender() {
  // 另一种坏法：**倾斜的透视条带** —— 四角落在窗口外，是空的。
  #expect(
    !WindowThumbnails.looksLikeWindowRender(
      image { context in
        context.setFillColor(opaque(0.2, 0.3, 0.4))
        context.fill(CGRect(x: 20, y: 0, width: 24, height: 64))
        context.setFillColor(opaque(0.9, 0.1, 0.1))
        context.fill(CGRect(x: 20, y: 8, width: 24, height: 8))
      }))
}
}

extension PanelAndThumbnailTests {
@Test func aWindowWithTransparentRoundedCornersPasses() {
  // 真窗口的**圆角本身就是透明的**：默认四角采样会把每一扇真窗口都判否
  // （实测 320pt 宽抓图，(0,0) 的 alpha = 0，内缩 2px 后 = 255）。
  // 所以四角采样内缩 2px —— 这条是那个修复的回归钉。
  #expect(
    WindowThumbnails.looksLikeWindowRender(
      image { context in
        context.setFillColor(opaque(0.15, 0.15, 0.17))
        context.addPath(
          CGPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.setFillColor(opaque(0.95, 0.95, 0.95))
        context.fill(CGRect(x: 0, y: 48, width: 64, height: 16))
      }))
}
}

extension PanelAndThumbnailTests {
@Test func anOrdinaryWindowRenderPasses() {
  // 真窗口：不透明 + 好多种颜色。深底 + 亮标题栏 + 一块内容。
  #expect(
    WindowThumbnails.looksLikeWindowRender(
      image { context in
        context.setFillColor(opaque(0.15, 0.15, 0.17))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(opaque(0.95, 0.95, 0.95))
        context.fill(CGRect(x: 0, y: 56, width: 64, height: 8))
        context.setFillColor(opaque(0.4, 0.6, 0.9))
        context.fill(CGRect(x: 8, y: 20, width: 30, height: 20))
      }))
}
}

// MARK: - capturePlan

// 「这一轮抓谁」是纯函数（`WindowThumbnails.capturePlan`）。下面这几个测试钉住的
// 是用户实测的 bug：面板里大部分卡片只有 app 图标 —— 因为**离屏窗口在合成层
// 没有渲染**，SCK 抓它们必然失败（-3811 / 斜条带 / 全白），而每次枚举都重试
// 既烧 IPC、又让它们永远算「正在抓」，把面板首帧拖满 warmUpDeadline。

/// 造一扇窗。默认在屏（`isOnscreen` 是 0.0.4 加的信号，只给缩略图用）。
private func window(_ id: UInt32, onscreen: Bool = true) -> Window {
  Window(
    pid: 42, windowID: id, appName: "App", title: "t\(id)",
    isMinimized: false, isOnscreen: onscreen)
}

extension PanelAndThumbnailTests {
@Test func aWindowWithoutAnImageMustBeCaptured() {
  // 没图 → 必抓（包括首帧要等的那份）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(1)], cached: [], busy: [], unrenderable: [])
  #expect(plan.needed == [1])
  #expect(plan.refresh.isEmpty)
}
}

extension PanelAndThumbnailTests {
@Test func anOffscreenWindowWithoutAnImageIsCapturedOnce() {
  // 没图 + 不在屏上 + 还没失败过 → 试一次（它可能就是能抓的那类窗口，不能因为
  // 「不在屏上」就预判失败 —— isOnscreen 在台前调度搁置的窗口上是会横跳的）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(7, onscreen: false)], cached: [], busy: [], unrenderable: [])
  #expect(plan.needed == [7])
}
}

extension PanelAndThumbnailTests {
@Test func anUnrenderableOffscreenWindowIsNotRetried() {
  // 试过、失败了、当时不在屏上 → 别再试（这就是「大部分卡片只有图标」的修法：
  // 失败的那批不再无限重试，改用缓存的那张图）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(7, onscreen: false)], cached: [], busy: [], unrenderable: [7])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh.isEmpty)
}
}

extension PanelAndThumbnailTests {
@Test func anUnrenderableWindowIsRetriedOnceItIsOnscreen() {
  // 它回到屏上了 —— 现在是能抓的，必须再试（用户切到那个 Space 之后要看到真图）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(7)], cached: [], busy: [], unrenderable: [7])
  #expect(plan.needed == [7])
}
}

extension PanelAndThumbnailTests {
@Test func aVisibleWindowWithAnImageIsRefreshed() {
  // 有图 + 在屏 → 刷新（可见窗口的内容会变）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(3)], cached: [3], busy: [], unrenderable: [])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh == [3])
}
}

extension PanelAndThumbnailTests {
@Test func aWindowThatIsNotOnscreenKeepsItsCachedImage() {
  // 有图 + 不在屏 → 既不该抓也不该刷：它显示的是缓存里那张「见到的最近一次」。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(3, onscreen: false)], cached: [3], busy: [], unrenderable: [3])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh.isEmpty)
}
}

extension PanelAndThumbnailTests {
@Test func windowsAlreadyInFlightAreNotResubmitted() {
  // 上一次枚举发出去的抓取还没回来 —— 别重复发 IPC（连续两次枚举很常见：
  // 切 app 会触发一次，按 ⌘Tab 又会触发一次）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(1), window(2), window(3)],
    cached: [2], busy: [1, 2, 3], unrenderable: [])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh.isEmpty)
}
}

extension PanelAndThumbnailTests {
@Test @MainActor func diskThumbnailReadsRunOffTheMainThread() async {
  let loaded = await WindowThumbnails.loadDiskImages([991], loader: { id in
    #expect(!isMainThread())
    #expect(id == 991)
    return image { context in
      context.setFillColor(opaque(0.2, 0.4, 0.6))
      context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
  })
  #expect(loaded[991]?.width == 64)
}
}

private actor DiskImageGate {
  private var continuation: CheckedContinuation<[UInt32: CGImage], Never>?
  private var started: CheckedContinuation<Void, Never>?
  func load() async -> [UInt32: CGImage] {
    await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
  }
  func waitUntilStarted() async {
    if continuation != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish(_ result: [UInt32: CGImage]) { continuation?.resume(returning: result); continuation = nil }
}

extension PanelAndThumbnailTests {
@Test @MainActor func lateDiskImagesCannotResurrectRemovedWindows() async throws {
  let gate = DiskImageGate()
  let target = window(999_991, onscreen: false)
  var finished = false
  WindowThumbnails.warm([target], diskLoader: { _ in await gate.load() },
    captureImages: { _ in [:] }, pruneImages: { _ in })
  await gate.waitUntilStarted()
  WindowThumbnails.whenSettled { finished = true }
  WindowThumbnails.warm([], diskLoader: { _ in [:] },
    captureImages: { _ in [:] }, pruneImages: { _ in })
  let thumbnail = image { $0.setFillColor(opaque(0.2, 0.4, 0.6)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
  await gate.finish([target.windowID: thumbnail])
  for _ in 0..<100 where !finished { try await Task.sleep(for: .milliseconds(10)) }
  #expect(WindowThumbnails.image(for: target) == nil)
  #expect(finished)
  #expect(!WindowThumbnails.hasPendingWork)
}
}

extension PanelAndThumbnailTests {
@Test func freshCapturesAcceptPerspectiveButRejectBlankImages() {
  let perspective = image { context in
    context.setFillColor(opaque(0.2, 0.3, 0.4))
    context.fill(CGRect(x: 20, y: 0, width: 24, height: 64))
    context.setFillColor(opaque(0.9, 0.1, 0.1))
    context.fill(CGRect(x: 20, y: 8, width: 24, height: 8))
  }
  #expect(WindowThumbnails.looksLikeWindowRender(perspective, source: .fresh))
  #expect(!WindowThumbnails.looksLikeWindowRender(perspective, source: .cached))
  for source in Settings.PreviewSource.allCases {
    #expect(!WindowThumbnails.looksLikeWindowRender(image { _ in }, source: source))
    #expect(!WindowThumbnails.looksLikeWindowRender(image {
      $0.setFillColor(opaque(1, 1, 1)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }, source: source))
  }
}
}

@Suite(.serialized) struct PanelAndThumbnailTests {}

private func isMainThread() -> Bool { Thread.isMainThread }

private actor CaptureCount {
  var ids: [UInt32] = []
  func record(_ new: [UInt32]) { ids += new }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func freshSessionsIgnoreDiskDeduplicateAndRetryOnReopen() async throws {
    let target = window(999_992, onscreen: false)
    let count = CaptureCount()
    WindowThumbnails.beginSession(source: .fresh)
    defer { WindowThumbnails.endSession(); WindowThumbnails.configure(source: .cached) }
    func warm() {
      WindowThumbnails.warm([target], diskLoader: { _ in Issue.record("Fresh must not load disk"); return [:] },
        captureImages: { ids in await count.record(ids); return [:] },
        pruneImages: { _ in Issue.record("Fresh must not prune disk") },
        saveImages: { _ in Issue.record("Fresh must not save disk") })
    }
    warm()
    for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    warm()
    #expect(await count.ids == [target.windowID])
    WindowThumbnails.endSession()
    warm()
    #expect(!WindowThumbnails.hasPendingWork)
    WindowThumbnails.beginSession(source: .fresh)
    warm()
    for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await count.ids == [target.windowID, target.windowID])
  }

  @Test(arguments: Settings.PreviewSource.allCases) @MainActor
  func modeChangeRejectsLateCaptureAndPersistence(_ source: Settings.PreviewSource) async throws {
    let target = window(999_993)
    let gate = DiskImageGate()
    WindowThumbnails.beginSession(source: source)
    WindowThumbnails.warm([target], diskLoader: { _ in [:] },
      captureImages: { _ in
        let images = await gate.load()
        #expect(Task.isCancelled)
        return images
      }, pruneImages: { _ in },
      saveImages: { _ in Issue.record("Stale capture must not persist") })
    await gate.waitUntilStarted()
    WindowThumbnails.beginSession(source: source == .cached ? .fresh : .cached)
    defer { WindowThumbnails.endSession(); WindowThumbnails.configure(source: .cached) }
    let thumbnail = image { $0.setFillColor(opaque(0.2, 0.4, 0.6)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
    await gate.finish([target.windowID: thumbnail])
    try await Task.sleep(for: .milliseconds(50))
    #expect(WindowThumbnails.image(for: target) == nil)
    #expect(!WindowThumbnails.hasPendingWork)
  }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func freshImagesEndWithTheirSessionAndVisibilityAllowsOneRetry() async throws {
    let id: UInt32 = 999_994
    let count = CaptureCount()
    let thumbnail = image { $0.setFillColor(opaque(0.2, 0.4, 0.6)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
    WindowThumbnails.beginSession(source: .fresh)
    defer { WindowThumbnails.endSession(); WindowThumbnails.configure(source: .cached) }
    func warm(onscreen: Bool, succeeds: Bool) {
      WindowThumbnails.warm([window(id, onscreen: onscreen)],
        captureImages: { ids in await count.record(ids); return succeeds ? [id: thumbnail] : [:] })
    }
    warm(onscreen: false, succeeds: false)
    for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    warm(onscreen: true, succeeds: true)
    for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    #expect(WindowThumbnails.image(for: window(id)) === thumbnail)
    warm(onscreen: true, succeeds: true)
    #expect(await count.ids == [id, id])
    WindowThumbnails.endSession()
    #expect(WindowThumbnails.image(for: window(id)) == nil)
    WindowThumbnails.beginSession(source: .fresh)
    #expect(WindowThumbnails.image(for: window(id)) == nil)
  }

  @Test @MainActor func freshVisibleFailuresDoNotLoop() async throws {
    let target = window(999_995)
    let count = CaptureCount()
    WindowThumbnails.beginSession(source: .fresh)
    defer { WindowThumbnails.endSession(); WindowThumbnails.configure(source: .cached) }
    for _ in 0..<3 {
      WindowThumbnails.warm([target], captureImages: { ids in await count.record(ids); return [:] })
      for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    }
    #expect(await count.ids == [target.windowID])
    #expect(WindowThumbnails.image(for: target) == nil)
  }

  @Test @MainActor func freshBatchesCaptureEachWindowOnceAtTenFiftyAndOneHundredWindows() async throws {
    for size in [10, 50, 100] {
      let windows = (1...size).map { window(UInt32(900_000 + $0)) }
      let count = CaptureCount()
      WindowThumbnails.beginSession(source: .fresh)
      for _ in 0..<10 {
        WindowThumbnails.warm(windows, captureImages: { ids in
          #expect(!isMainThread())
          await count.record(ids); return [:]
        })
      }
      for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
      #expect(await count.ids.count == size)
      #expect(await Set(count.ids).count == size)
      WindowThumbnails.endSession()
    }
    WindowThumbnails.configure(source: .cached)
  }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func beginningFreshSessionNotifiesCardsToDropTheirPreviousImages() {
    WindowThumbnails.beginSession(source: .fresh)
    var changes = 0
    let previous = WindowThumbnails.onChange
    WindowThumbnails.onChange = { changes += 1 }
    defer {
      WindowThumbnails.onChange = previous
      WindowThumbnails.endSession(); WindowThumbnails.configure(source: .cached)
    }
    WindowThumbnails.endSession()
    #expect(changes == 0)
    WindowThumbnails.beginSession(source: .fresh)
    #expect(changes == 1)
  }
}

private final class SavedImages: @unchecked Sendable {
  private let lock = NSLock()
  private var ids: Set<UInt32> = []
  func save(_ images: [UInt32: CGImage]) {
    #expect(!Thread.isMainThread)
    lock.withLock { ids.formUnion(images.keys) }
  }
  var savedIDs: Set<UInt32> { lock.withLock { ids } }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func cachedCapturesStillPersistOffTheMainThread() async throws {
    WindowThumbnails.configure(source: .cached)
    let target = window(999_996)
    let saved = SavedImages()
    let thumbnail = image { $0.setFillColor(opaque(0.2, 0.4, 0.6)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
    WindowThumbnails.warm([target], diskLoader: { _ in [:] },
      captureImages: { _ in [target.windowID: thumbnail] }, pruneImages: { _ in },
      saveImages: { saved.save($0) })
    for _ in 0..<100 where saved.savedIDs.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    #expect(saved.savedIDs == [target.windowID])
    #expect(WindowThumbnails.image(for: target) === thumbnail)
    WindowThumbnails.configure(source: .fresh)
    WindowThumbnails.configure(source: .cached)
  }
}

private final class DiskWriteGate: @unchecked Sendable {
  private let lock = NSLock()
  private let release = DispatchSemaphore(value: 0)
  private var started = 0
  var count: Int { lock.withLock { started } }
  func save() {
    lock.withLock { started += 1 }
    _ = release.wait(timeout: .now() + 2)
  }
  func finish() { release.signal(); release.signal() }
}

extension PanelAndThumbnailTests {
  @Test(arguments: [false, true]) @MainActor
  func cachedDiskWritesDoNotOverlapAndModeChangeCancelsQueuedWrites(_ cancel: Bool) async throws {
    WindowThumbnails.configure(source: .cached)
    let gate = DiskWriteGate()
    defer { gate.finish() }
    let first = window(999_997, onscreen: false)
    let second = window(999_998, onscreen: false)
    let thumbnail = image { $0.setFillColor(opaque(0.2, 0.4, 0.6)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
    func warm(_ windows: [Window]) {
      WindowThumbnails.warm(windows, diskLoader: { _ in [:] },
        captureImages: { ids in Dictionary(uniqueKeysWithValues: ids.map { ($0, thumbnail) }) },
        pruneImages: { _ in }, saveImages: { _ in gate.save() })
    }
    warm([first])
    for _ in 0..<100 where gate.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(gate.count == 1)
    warm([first, second])
    for _ in 0..<100 where WindowThumbnails.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(WindowThumbnails.image(for: second) === thumbnail)
    #expect(gate.count == 1, "Second save must wait for the first without blocking image publication")
    if cancel { WindowThumbnails.configure(source: .fresh) }
    gate.finish()
    try await Task.sleep(for: .milliseconds(50))
    #expect(gate.count == (cancel ? 1 : 2))
    WindowThumbnails.configure(source: .fresh)
    WindowThumbnails.configure(source: .cached)
  }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func switchingModesBeforeWarmStartsSkipsQueuedDiskLoading() async throws {
    WindowThumbnails.configure(source: .cached)
    WindowThumbnails.warm([window(999_999)],
      diskLoader: { _ in Issue.record("Invalidated warm must not start disk loading"); return [:] },
      captureImages: { _ in Issue.record("Invalidated warm must not capture"); return [:] },
      pruneImages: { _ in })
    WindowThumbnails.configure(source: .fresh)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!WindowThumbnails.hasPendingWork)
    WindowThumbnails.configure(source: .cached)
  }
}

extension PanelAndThumbnailTests {
  @Test @MainActor func cancelledDiskReadFinishesItsCurrentFileButSkipsTheNext() async throws {
    let gate = DiskWriteGate()
    defer { gate.finish() }
    let thumbnail = image { _ in }
    let task = Task {
      await WindowThumbnails.loadDiskImages([1, 2], loader: { _ in gate.save(); return thumbnail })
    }
    for _ in 0..<100 where gate.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(gate.count == 1)
    task.cancel()
    gate.finish()
    let loaded = await task.value
    #expect(Set(loaded.keys) == [1])
    #expect(gate.count == 1)
  }
}
