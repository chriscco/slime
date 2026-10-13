import ApplicationServices
import CoreGraphics
import Testing

@testable import slime

// 窗口过滤的纯函数（System 层唯一能单测的部分）。两个真机 bug 的回归：
// - #21：系统给每个 app 生的幽灵窗口（不在屏上、不在 AX 里）不得进列表；
// - #23：`kAXWindows` 只给当前 Space 的窗口 —— 见过一次的窗口离屏后必须还在。

private func candidate(
  _ id: UInt32,
  onscreen: Bool = false,
  matched: KnownWindow? = nil,
  helper: Bool = false,
  app: String = "App"
) -> WindowCandidate {
  WindowCandidate(
    windowID: id, pid: 1, appName: app, onscreen: onscreen, matched: matched, helper: helper)
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
      candidate(2, matched: KnownWindow(appName: "App", title: "Code — 标题", minimized: false)),
    ],
    known: [:]
  )
  #expect(result.windows.map(\.windowID) == [1, 2])
  #expect(result.known[1] != nil)
  #expect(result.known[2]?.title == "Code — 标题")
}

@Test func rememberedOffscreenWindowStaysWithItsTitle() {
  // 第二块屏幕 / 访问过的 Space：见过一次，之后离屏仍在（issue #23）。
  let known: [UInt32: KnownWindow] = [7: KnownWindow(appName: "App", title: "Welcome — slime", minimized: false)]
  let result = WindowEnumerator.select([candidate(7)], known: known)
  #expect(result.windows.map(\.windowID) == [7])
  #expect(result.windows.first?.title == "Welcome — slime")
  #expect(result.known[7] != nil)  // 继续留用
}

@Test func knownEntryWithADifferentAppNameIsIgnored() {
  // known 表跨 slime 重启存活（windowID 同一次开机内稳定），但**重启机器**后
  // windowID 可能被复用 —— 名字对不上的条目按不认识处理（用户实测：重启后
  // 只剩下一个窗口，这条持久化修复的另一半是它的防误判）。
  let known: [UInt32: KnownWindow] = [
    7: KnownWindow(appName: "Chrome", title: "旧窗口", minimized: false)
  ]
  let result = WindowEnumerator.select([candidate(7, app: "Finder")], known: known)
  #expect(result.windows.isEmpty)  // 不是 Finder 的窗口 → 不认识 → 只有 known 的 id 也不算数
}

@Test func knownTableSurvivesABinaryRoundTrip() throws {
  // 持久化的编码/解码形状：跨 slime 重启存活靠它。
  let known: [UInt32: KnownWindow] = [
    1: KnownWindow(appName: "ZCode", title: "项目", minimized: false),
    2: KnownWindow(appName: "Chrome", title: "GitHub", minimized: true),
  ]
  let stored = known.map { StoredKnownWindow(id: $0.key, entry: $0.value) }
  let data = try JSONEncoder().encode(stored)
  let decoded = try JSONDecoder().decode([StoredKnownWindow].self, from: data)
  #expect(Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0.entry) }) == known)
}

@Test func vanishedWindowsArePrunedFromKnown() {
  // 窗口消失（这一轮不在候选里）→ known 表自然修剪，防 id 复用误判。
  let known: [UInt32: KnownWindow] = [
    1: KnownWindow(appName: "App", title: "A", minimized: false),
    2: KnownWindow(appName: "App", title: "B", minimized: false),
  ]
  let result = WindowEnumerator.select([candidate(1, onscreen: true)], known: known)
  #expect(result.known.keys.sorted() == [1])
}

@Test func freshMatchInfoWinsOverMemory() {
  let known: [UInt32: KnownWindow] = [3: KnownWindow(appName: "App", title: "旧标题", minimized: false)]
  let result = WindowEnumerator.select(
    [candidate(3, matched: KnownWindow(appName: "App", title: "新标题", minimized: true))],
    known: known
  )
  #expect(result.known[3] == KnownWindow(appName: "App", title: "新标题", minimized: true))
}

@Test func rememberedMinimizedStateSurvivesOffscreen() {
  let known: [UInt32: KnownWindow] = [9: KnownWindow(appName: "App", title: "T", minimized: true)]
  let result = WindowEnumerator.select([candidate(9)], known: known)
  #expect(result.windows.first?.isMinimized == true)
}

// 用户实测：Chrome 只有 3 个窗口、面板却显示 7 行。Chromium 经 AX 把菜单栏 /
// 工具栏条报成窗口 —— subrole=AXUnknown、无标题，且 onscreen / AX matched /
// known 三条正面证据全命中。助手判定必须优先否决，且不进 known
//（用户现有的 7 行会在下一次枚举自愈回 3 行）。
@Test func helperStripsAreDroppedEvenWithOnscreenOrKnownEvidence() {
  let known: [UInt32: KnownWindow] = [1: KnownWindow(appName: "App", title: "", minimized: false)]
  let result = WindowEnumerator.select(
    [
      candidate(1, onscreen: true, helper: true),  // 在屏上 + known，仍要丢
      candidate(2, onscreen: true),  // 真窗口，对照
    ],
    known: known
  )
  #expect(result.windows.map(\.windowID) == [2])
  #expect(result.known.keys.sorted() == [2])  // 助手不进 known
}

// 助手判定只看「AXUnknown + 空标题」：AXStandardWindow（实测真窗口全是它）
// 不否决；AXUnknown 但有标题也不否决；读不到 subrole（空串）不否决。
@Test func helperPredicateOnlyMatchesUnknownSubroleWithEmptyTitle() {
  #expect(AXWindows.isHelper(subrole: kAXUnknownSubrole, title: ""))
  #expect(!AXWindows.isHelper(subrole: kAXStandardWindowSubrole, title: ""))
  #expect(!AXWindows.isHelper(subrole: kAXUnknownSubrole, title: "德云色 JDG VS BFX"))
  #expect(!AXWindows.isHelper(subrole: "", title: ""))
}

// 显示器范围（注入纯函数）：主屏 + 左上方副屏。
private let displays: [CGRect] = [
  CGRect(x: 0, y: 0, width: 1470, height: 956),
  CGRect(x: -582, y: 956, width: 1920, height: 1080),
]

@Test func windowOutsideEveryDisplayIsDropped() {
  // Chromium 的助手条：@(-1920,0) 1920x41 —— 与两个显示器都不相交。
  let strip = CGRect(x: -1920, y: 0, width: 1920, height: 41)
  #expect(!WindowEnumerator.isOnAnyDisplay(strip, displays: displays))
}

@Test func stageManagerStripAndFullscreenWindowAreOnDisplay() {
  // 台前调度条带（屏内的小方框）与全屏窗口都在屏内 —— 红线 7 的「不按尺寸」
  // 不被这条过滤破坏。
  #expect(
    WindowEnumerator.isOnAnyDisplay(CGRect(x: 0, y: 0, width: 160, height: 900), displays: displays))
  #expect(
    WindowEnumerator.isOnAnyDisplay(
      CGRect(x: 0, y: 0, width: 1470, height: 956), displays: displays))
}
