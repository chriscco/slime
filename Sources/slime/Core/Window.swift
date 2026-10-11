// Core/ —— 纯逻辑层。只 import Foundation 和标准库，
// 不碰 AppKit / CoreGraphics / ApplicationServices —— 保住 Trigger 和 Search
// 能在没有辅助功能权限、没有 CGEventTap、没有真人的情况下被单测穷举
// （CLAUDE.md 第六条）。

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

  public init(
    pid: pid_t,
    windowID: UInt32,
    appName: String,
    title: String,
    isMinimized: Bool
  ) {
    self.pid = pid
    self.windowID = windowID
    self.appName = appName
    self.title = title
    self.isMinimized = isMinimized
  }

  /// 列表显示与搜索匹配共用的拼接串：`app名 — 标题`。
  /// 搜 `chrome` 和搜标题片段因此命中同一批结果（spec §7）。
  public var label: String {
    title.isEmpty ? appName : "\(appName) — \(title)"
  }
}
