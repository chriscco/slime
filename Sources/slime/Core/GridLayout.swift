// Core/ —— 纯逻辑层，见 Window.swift 顶部注释。
//
// 只用 Swift 基本类型：CGSize / NSRect 是 CoreGraphics 的，这一层不许碰
// （CLAUDE.md 第六条；Window.swift 用 UInt32 而不是 CGWindowID 是同一个理由）。

import Foundation

/// 卡片网格的几何（spec §5.1）。纯函数，UI 层拿它算 frame。
public struct GridLayout: Equatable, Sendable {
  /// 一排最多 3 张。卡片 240×176（图区 240×150），3 列满排 792pt ——
  /// 1366 宽的屏也放得下；1280 以下要再收的话先减 `maxColumns`。
  public static let maxColumns = 3

  public let count: Int
  public let columns: Int
  public let rows: Int
  /// 只显示这么多排，其余靠滚动。
  public let visibleRows: Int
  public let cardWidth: Double
  public let cardHeight: Double
  public let gap: Double
  public let padding: Double
  /// 搜索框那一块的高度（含上下留白）。
  public let headerHeight: Double

  // shortcut: 网格常量（卡片尺寸 / 间隙 / 最多 3 行可见）是编译期常量，
  //           被嫌弃时再做可配置（spec §14）
  public init(
    count: Int,
    // 卡片按 16:10 的窗口缩略图配：图区 240×150，下面是标题。
    // spec 0.0.3 §5.4 的 160×120 是给图标量身的提案值，实机看缩略图太小。
    cardWidth: Double = 240,
    cardHeight: Double = 176,
    gap: Double = 16,
    padding: Double = 20,
    headerHeight: Double = 46,
    maxVisibleRows: Int = 3
  ) {
    let n = max(0, count)
    self.count = n
    self.cardWidth = cardWidth
    self.cardHeight = cardHeight
    self.gap = gap
    self.padding = padding
    self.headerHeight = headerHeight
    self.columns = min(n, Self.maxColumns)
    self.rows = (n + Self.maxColumns - 1) / Self.maxColumns
    self.visibleRows = min(rows, max(0, maxVisibleRows))
  }

  /// 网格本身的宽（不含 padding）。
  public var gridWidth: Double {
    Double(columns) * cardWidth + Double(max(0, columns - 1)) * gap
  }

  /// 网格本身的高（不含 padding 和 headerHeight），只算可见的排。
  public var gridHeight: Double {
    Double(visibleRows) * cardHeight + Double(max(0, visibleRows - 1)) * gap
  }

  /// 文档视图的完整高度（含滚动出去的那几排）—— 面板高度只看 visibleRows，
  /// 但文档视图要能滚到第 4 排以后。
  public var contentHeight: Double {
    Double(rows) * cardHeight + Double(max(0, rows - 1)) * gap
  }

  public var panelWidth: Double { 2 * padding + gridWidth }
  public var panelHeight: Double { 2 * padding + headerHeight + gridHeight }

  /// 第 index 张卡在**网格坐标系**（左上角原点、y 向下）里的位置。
  /// 不含 padding / headerHeight —— 那是面板内容视图的活。
  public func origin(of index: Int) -> (x: Double, y: Double) {
    guard columns > 0 else { return (0, 0) }
    return (
      Double(index % columns) * (cardWidth + gap),
      Double(index / columns) * (cardHeight + gap)
    )
  }

  /// 位移没跨行、或只跨一排 → 动画；跨更多排 → 直接跳。
  ///
  /// 只判「首尾回绕」不够：4 列网格里 ↑ 在首排往上走会绕到末排，
  /// 那种斜穿同样难看。按行距判一条规则覆盖两种情况。
  ///
  /// shortcut: 按行距判（跨 >1 排就跳），没做「按像素距离 / 按方向」的更细的
  ///           手感调优 —— 真的觉得某些移动的动画多余时再说（spec §14）
  public func shouldAnimate(from: Int, to: Int) -> Bool {
    guard count > 0, rows > 1, columns > 0 else { return true }
    return abs((to / columns) - (from / columns)) <= 1
  }
}
