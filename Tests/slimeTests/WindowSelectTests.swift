import Testing

@testable import slime

// 窗口过滤的纯函数（System 层唯一能单测的部分）。两个真机 bug 的回归：
// - #21：系统给每个 app 生的幽灵窗口（不在屏上、不在 AX 里）不得进列表；
// - #23：`kAXWindows` 只给当前 Space 的窗口 —— 见过一次的窗口离屏后必须还在。

private func candidate(
  _ id: UInt32,
  onscreen: Bool = false,
  matched: KnownWindow? = nil,
  app: String = "App"
) -> WindowCandidate {
  WindowCandidate(windowID: id, pid: 1, appName: app, onscreen: onscreen, matched: matched)
}

@Test func ghostWindowsNeverEnterTheList() {
  // 幽灵：不在屏上、AX 里没有、也没见过。
  let result = WindowEnumerator.select([candidate(1), candidate(2)], known: [:])
  #expect(result.windows.isEmpty)
  #expect(result.known.isEmpty)
}

@Test func onscreenAndMatchedWindowsPass() {
  let result = WindowEnumerator.select(
    [
      candidate(1, onscreen: true),
      candidate(2, matched: KnownWindow(title: "Code — 标题", minimized: false)),
    ],
    known: [:]
  )
  #expect(result.windows.map(\.windowID) == [1, 2])
  #expect(result.known[1] != nil)
  #expect(result.known[2]?.title == "Code — 标题")
}

@Test func rememberedOffscreenWindowStaysWithItsTitle() {
  // 第二块屏幕 / 访问过的 Space：见过一次，之后离屏仍在（issue #23）。
  let known: [UInt32: KnownWindow] = [7: KnownWindow(title: "Welcome — slime", minimized: false)]
  let result = WindowEnumerator.select([candidate(7)], known: known)
  #expect(result.windows.map(\.windowID) == [7])
  #expect(result.windows.first?.title == "Welcome — slime")
  #expect(result.known[7] != nil)  // 继续留用
}

@Test func vanishedWindowsArePrunedFromKnown() {
  // 窗口消失（这一轮不在候选里）→ known 表自然修剪，防 id 复用误判。
  let known: [UInt32: KnownWindow] = [
    1: KnownWindow(title: "A", minimized: false),
    2: KnownWindow(title: "B", minimized: false),
  ]
  let result = WindowEnumerator.select([candidate(1, onscreen: true)], known: known)
  #expect(result.known.keys.sorted() == [1])
}

@Test func freshMatchInfoWinsOverMemory() {
  let known: [UInt32: KnownWindow] = [3: KnownWindow(title: "旧标题", minimized: false)]
  let result = WindowEnumerator.select(
    [candidate(3, matched: KnownWindow(title: "新标题", minimized: true))],
    known: known
  )
  #expect(result.known[3] == KnownWindow(title: "新标题", minimized: true))
}

@Test func rememberedMinimizedStateSurvivesOffscreen() {
  let known: [UInt32: KnownWindow] = [9: KnownWindow(title: "T", minimized: true)]
  let result = WindowEnumerator.select([candidate(9)], known: known)
  #expect(result.windows.first?.isMinimized == true)
}
