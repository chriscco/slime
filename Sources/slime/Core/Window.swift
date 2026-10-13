// Core/ —— 纯逻辑层。只 import Foundation 和标准库，
// 不碰 AppKit / CoreGraphics / ApplicationServices —— 保住 Trigger 和 Search
// 能在没有辅助功能权限、没有 CGEventTap、没有真人的情况下被单测穷举
// （CLAUDE.md 第六条）。
//
// shortcut: Core/ 的分层守卫测试已补（Tests/slimeTests/LayeringTests.swift，
// 拦「谁 import 了 AppKit / CoreGraphics / ApplicationServices」）——
// 纯逻辑层现在 4 个文件（Window / Search / Trigger / GridLayout）。

import Foundation

/// 一个可切换到的窗口。不可变值类型：快照整体替换、跨线程传递，天然无锁（红线 8）。
public struct Window: Equatable, Sendable {
  public let pid: pid_t
  /// CGWindowList 的窗口编号。用 UInt32 而不是 CGWindowID ——
  /// 那是 CoreGraphics 的类型，这一层不许碰。
  public let windowID: UInt32
  public let appName: String
  /// 窗口标题。AX 拿不到（超时/无权限）时留空，由 `label` 退化成 app 名（红线 6）。
  public let title: String
  public let isMinimized: Bool
  /// `kCGWindowIsOnscreen`。**只用于缩略图**：在屏上的窗口合成层才有渲染，
  /// 抓它才拿得到真图（其他 Space / 最小化 / 台前调度搁置的窗口抓不了，
  /// 见 `WindowThumbnails`）。**不是用来过滤窗口的** —— 台前调度搁置的窗口
  /// 这个值会在 0/1 之间反复横跳（spec §4.3 实测），拿它筛列表会漏窗。
  ///
  /// 默认 true（「不知道就算它能抓」）：唯一的生产构造点在 `WindowEnumerator`，
  /// 那里总是显式传值；默认值只影响测试构造。
  public let isOnscreen: Bool

  public init(
    pid: pid_t,
    windowID: UInt32,
    appName: String,
    title: String,
    isMinimized: Bool,
    isOnscreen: Bool = true
  ) {
    self.pid = pid
    self.windowID = windowID
    self.appName = appName
    self.title = title
    self.isMinimized = isMinimized
    self.isOnscreen = isOnscreen
  }

  /// 列表显示与搜索匹配共用的拼接串：`app名 — 标题`。
  /// 搜 `chrome` 和搜标题片段因此命中同一批结果（spec §7）。
  public var label: String {
    title.isEmpty ? appName : "\(appName) — \(title)"
  }
}
