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
