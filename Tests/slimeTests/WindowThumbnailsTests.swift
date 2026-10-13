import CoreGraphics
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

@Test func anEmptyImageIsNotAWindowRender() {
  // 抓空的极端情形：整张全透明。
  #expect(!WindowThumbnails.looksLikeWindowRender(image { _ in }))
}

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

@Test func aWindowWithoutAnImageMustBeCaptured() {
  // 没图 → 必抓（包括首帧要等的那份）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(1)], cached: [], busy: [], unrenderable: [])
  #expect(plan.needed == [1])
  #expect(plan.refresh.isEmpty)
}

@Test func anOffscreenWindowWithoutAnImageIsCapturedOnce() {
  // 没图 + 不在屏上 + 还没失败过 → 试一次（它可能就是能抓的那类窗口，不能因为
  // 「不在屏上」就预判失败 —— isOnscreen 在台前调度搁置的窗口上是会横跳的）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(7, onscreen: false)], cached: [], busy: [], unrenderable: [])
  #expect(plan.needed == [7])
}

@Test func anUnrenderableOffscreenWindowIsNotRetried() {
  // 试过、失败了、当时不在屏上 → 别再试（这就是「大部分卡片只有图标」的修法：
  // 失败的那批不再无限重试，改用缓存的那张图）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(7, onscreen: false)], cached: [], busy: [], unrenderable: [7])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh.isEmpty)
}

@Test func anUnrenderableWindowIsRetriedOnceItIsOnscreen() {
  // 它回到屏上了 —— 现在是能抓的，必须再试（用户切到那个 Space 之后要看到真图）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(7)], cached: [], busy: [], unrenderable: [7])
  #expect(plan.needed == [7])
}

@Test func aVisibleWindowWithAnImageIsRefreshed() {
  // 有图 + 在屏 → 刷新（可见窗口的内容会变）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(3)], cached: [3], busy: [], unrenderable: [])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh == [3])
}

@Test func aWindowThatIsNotOnscreenKeepsItsCachedImage() {
  // 有图 + 不在屏 → 既不该抓也不该刷：它显示的是缓存里那张「见到的最近一次」。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(3, onscreen: false)], cached: [3], busy: [], unrenderable: [3])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh.isEmpty)
}

@Test func windowsAlreadyInFlightAreNotResubmitted() {
  // 上一次枚举发出去的抓取还没回来 —— 别重复发 IPC（连续两次枚举很常见：
  // 切 app 会触发一次，按 ⌘Tab 又会触发一次）。
  let plan = WindowThumbnails.capturePlan(
    windows: [window(1), window(2), window(3)],
    cached: [2], busy: [1, 2, 3], unrenderable: [])
  #expect(plan.needed.isEmpty)
  #expect(plan.refresh.isEmpty)
}
