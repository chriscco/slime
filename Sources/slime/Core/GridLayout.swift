import Foundation

/// Five fixed columns. Group headers add space without becoming selectable cells.
public struct GridLayout: Equatable, Sendable {
  public static let maxColumns = 5
  public static let groupHeaderHeight = 28.0
  public let count: Int
  public let columns = maxColumns
  public let rows: Int
  public let visibleRows: Int
  private let rowLimit: Int
  public let cardWidth: Double
  public let cardHeight: Double
  public let gap: Double
  public let padding: Double
  public let headerHeight: Double
  public let groupStarts: [Int]
  public let rowStarts: [Int]

  public init(
    count: Int, cardWidth: Double = 200, cardHeight: Double = 160,
    gap: Double = 12, padding: Double = 20, headerHeight: Double = 52,
    maxVisibleRows: Int = 3, groupStarts: [Int] = [], availableWidth: Double? = nil
  ) {
    let n = max(0, count)
    self.count = n
    let width = availableWidth.map { max(1, ($0 - 2 * padding - 4 * gap) / 5) }
    self.cardWidth = min(cardWidth, width ?? cardWidth)
    self.cardHeight = cardHeight - (cardWidth - self.cardWidth) / 1.6
    self.gap = gap
    self.padding = padding
    self.headerHeight = headerHeight
    let groups = Set(groupStarts.filter { $0 >= 0 && $0 < n })
    self.groupStarts = groups.isEmpty ? [] : groups.union([0]).sorted()
    var starts: [Int] = []
    for index in 0..<n {
      if index == 0 || groups.contains(index) || index - (starts.last ?? 0) == Self.maxColumns {
        starts.append(index)
      }
    }
    rowStarts = starts
    rows = starts.count
    rowLimit = max(0, maxVisibleRows)
    visibleRows = min(max(1, rows), rowLimit)
  }

  public var gridWidth: Double { Double(columns) * cardWidth + Double(columns - 1) * gap }
  public var gridHeight: Double {
    let limit = Double(rowLimit) * cardHeight + Double(max(0, rowLimit - 1)) * gap
    return count == 0 ? Double(visibleRows) * cardHeight : min(contentHeight, limit)
  }
  public var contentHeight: Double { count == 0 ? 0 : origin(of: count - 1).y + cardHeight }
  public var panelWidth: Double { 2 * padding + gridWidth }
  public var panelHeight: Double { 2 * padding + headerHeight + gridHeight }

  public func row(of index: Int) -> Int {
    rowStarts.lastIndex(where: { $0 <= index }) ?? 0
  }

  public func origin(of index: Int) -> (x: Double, y: Double) {
    guard count > 0 else { return (0, 0) }
    let row = row(of: index)
    let headings = groupStarts.filter { $0 <= index }.count
    return (Double(index - rowStarts[row]) * (cardWidth + gap),
      Double(row) * (cardHeight + gap) + Double(headings) * Self.groupHeaderHeight)
  }

  public func shouldAnimate(from: Int, to: Int) -> Bool { row(of: from) == row(of: to) }

  public func movedSelection(from selection: Int, axis: Axis, step: Int) -> Int {
    guard count > 0 else { return 0 }
    let current = min(max(selection, 0), count - 1)
    if axis == .horizontal { return ((current + step) % count + count) % count }
    let row = row(of: current)
    let column = current - rowStarts[row]
    let targetRow = ((row + step) % rows + rows) % rows
    let end = targetRow + 1 < rows ? rowStarts[targetRow + 1] : count
    return min(rowStarts[targetRow] + column, end - 1)
  }
}
