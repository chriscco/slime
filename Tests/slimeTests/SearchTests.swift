import Testing

@testable import slime

private func w(_ app: String, _ title: String, id: UInt32 = 1) -> Window {
  Window(pid: 1, windowID: id, appName: app, title: title, isMinimized: false)
}

// Window.label 是列表显示和搜索匹配共用的拼接串：app名 + " — " + 标题。
@Test func labelJoinsAppAndTitle() {
  #expect(w("Chrome", "GitHub").label == "Chrome — GitHub")
}

@Test func labelFallsBackToAppNameWithoutTitle() {
  #expect(w("Finder", "").label == "Finder")
}

// 空 query：原样返回，保持输入的 MRU 顺序。
@Test func rankWithEmptyQueryKeepsMRUOrder() {
  let windows = [w("A", "1", id: 1), w("B", "2", id: 2), w("C", "3", id: 3)]
  #expect(Search.rank(windows, query: "").map(\.windowID) == [1, 2, 3])
}

// 打字即时搜索的核心用例（spec §2 第 5 条）：`ghb` 能命中 `Chrome — GitHub`。
@Test func rankFindsSubsequenceAcrossAppAndTitle() {
  let windows = [w("Chrome", "GitHub", id: 1), w("Terminal", "zsh", id: 2)]
  #expect(Search.rank(windows, query: "ghb").map(\.windowID) == [1])
}

// 子序列不要求连续。
@Test func rankFindsNonContiguousSubsequence() {
  let windows = [w("Chrome", "GitHub")]
  #expect(Search.rank(windows, query: "chrm").count == 1)
}

// 大小写不敏感。
@Test func rankIsCaseInsensitive() {
  let windows = [w("Chrome", "GitHub")]
  #expect(Search.rank(windows, query: "GITHUB").count == 1)
}

// 搜 app 名和搜标题片段命中同一批结果 —— 匹配的是拼接串。
@Test func rankMatchesAppNameAndTitleThroughSameString() {
  let windows = [w("Chrome", "GitHub")]
  #expect(Search.rank(windows, query: "chrome").count == 1)
  #expect(Search.rank(windows, query: "git").count == 1)
}

// 无匹配：空数组。
@Test func rankReturnsEmptyWhenNothingMatches() {
  let windows = [w("Chrome", "GitHub")]
  #expect(Search.rank(windows, query: "xyz").isEmpty)
}

// 有 query：得分降序，压过 MRU 顺序。命中得更紧凑的排更前。
@Test func rankSortsByScoreDescending() {
  let gapped = w("X", "axb", id: 2)       // a、b 之间隔一个字符
  let contiguous = w("X", "ab", id: 1)    // a、b 连续
  #expect(Search.rank([gapped, contiguous], query: "ab").map(\.windowID) == [1, 2])
}

// 连续命中 / 词首命中比散落命中分高。
@Test func rankPrefersWordBoundaryOverInteriorScatter() {
  let boundary = w("X", "a_b", id: 1)  // b 落在词首（_ 之后）
  let interior = w("X", "zab", id: 2)  // b 只是相邻，a 不在词首
  #expect(Search.rank([interior, boundary], query: "ab").map(\.windowID) == [1, 2])
}

// 得分相同：保持输入的 MRU 顺序（输入即 MRU）。
@Test func rankKeepsMRUOrderOnScoreTie() {
  let first = w("Chrome", "GitHub", id: 1)
  let second = w("Chromium", "NightShift", id: 2)
  #expect(Search.rank([first, second], query: "chr").map(\.windowID) == [1, 2])
}

@Test func chineseAndMixedQueriesPreserveMatchingAndTieOrder() {
  let windows = [w("Safari", "工作 🐱", id: 9), w("Safari", "工作 🐱", id: 2), w("Notes", "周报", id: 7)]
  #expect(Search.rank(windows, query: "工作").map(\.windowID) == [9, 2])
  #expect(Search.rank(windows, query: "safari工作🐱").map(\.windowID) == [9, 2])
  #expect(Search.rank(windows, query: "").map(\.windowID) == [9, 2, 7])
  #expect(Search.rank(windows, query: "周报").map(\.windowID) == [7])
}
