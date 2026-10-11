// Core/ —— 纯逻辑层，见 Window.swift 顶部注释。

/// 打字即时搜索：fuzzy 子序列匹配 + 排序。纯函数（spec §10 的单测对象之一）。
public enum Search {
  /// 过滤 + 排序。
  ///
  /// - `windows` 按 MRU 序进来（WindowCache 负责）；
  /// - 空 query 原样返回 —— 无 query 时按 MRU 就是「不重排」；
  /// - 有 query：命中的按得分降序，得分相同保持 MRU 相对顺序；
  /// - 无命中返回空数组。
  public static func rank(_ windows: [Window], query: String) -> [Window] {
    guard !query.isEmpty else { return windows }

    let needle = Array(query.lowercased())
    let hits = windows.compactMap { window -> (window: Window, score: Int)? in
      Score.match(window.label, needle).map { (window, $0) }
    }

    // 显式带上原下标：Swift 的 sort 不保证稳定，而「得分相同按 MRU」要求稳定。
    return hits.enumerated()
      .sorted { a, b in
        a.element.score != b.element.score
          ? a.element.score > b.element.score
          : a.offset < b.offset
      }
      .map { $0.element.window }
  }
}

/// 打分。贪心从左到右取最早命中 —— 0.0.1 不需要 fzf 的最优对齐，
/// 贪心版本简单、可解释、可穷举进测试。
private enum Score {
  /// 把 query 的字符按顺序在 label 里找子序列。命中返回得分，未命中返回 nil。
  ///
  /// 每个命中字符：
  ///   +1 基础分
  ///   +1 与前一个命中字符相邻（连续）
  ///   +1 落在词首（label 开头，或前一个字符是空格 / 连字符 / 下划线）
  ///
  /// 连续和词首权重相同：`a_b` 与 `ab` 的匹配质量一样好。
  static func match(_ label: String, _ query: [Character]) -> Int? {
    let hay = Array(label.lowercased())
    var score = 0
    var searchFrom = 0
    var lastMatch: Int?

    for char in query {
      var hit: Int?
      var i = searchFrom
      while i < hay.count {
        if hay[i] == char {
          hit = i
          break
        }
        i += 1
      }
      guard let i = hit else { return nil }

      score += 1
      if let last = lastMatch, i == last + 1 { score += 1 }
      if i == 0 || Self.isBoundary(hay[i - 1]) { score += 1 }

      lastMatch = i
      searchFrom = i + 1
    }
    return score
  }

  private static func isBoundary(_ char: Character) -> Bool {
    char == " " || char == "-" || char == "—" || char == "_"
  }
}
