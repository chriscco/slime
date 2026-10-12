import Foundation
import Testing

@testable import slime

// 冷启动后「同一个 app 的窗口在列表里交错」这个 bug 的回归钉（spec §10）。
// 根因：没进过 MRU 的 app 全拿 `rank = Int.max`，名次并列 → 退回窗口列表的
// z 序 → 交错。`mruPids` 启动时是空的，所以冷启动必然如此。

private func window(pid: pid_t, id: UInt32) -> Window {
  Window(pid: pid, windowID: id, appName: "app\(pid)", title: "w\(id)", isMinimized: false)
}

/// 排序结果只取 pid 序列 —— 断言读起来就是「谁排在谁前面」。
private func pids(_ windows: [Window]) -> [pid_t] { windows.map(\.pid) }

@Test func windowsOfOneAppEndUpAdjacentEvenWithNoMRU() {
  // 交错输入 [1,2,1,2]：修之前输出还是 [1,2,1,2]（全部并列）。
  let input = [window(pid: 1, id: 10), window(pid: 2, id: 20),
               window(pid: 1, id: 11), window(pid: 2, id: 21)]
  #expect(pids(WindowCache.sort(input, byMRU: [])) == [1, 1, 2, 2])
}

@Test func unrankedAppsKeepTheirFirstAppearanceOrder() {
  // 都没进过 MRU：按在窗口列表里第一次出现的位置编号，用过的 app 排前面。
  let input = [window(pid: 3, id: 30), window(pid: 1, id: 10), window(pid: 2, id: 20),
               window(pid: 1, id: 11), window(pid: 3, id: 31)]
  #expect(pids(WindowCache.sort(input, byMRU: [])) == [3, 3, 1, 1, 2])
}

@Test func mruAppsComeFirstInMRUOrderAndUnrankedFollow() {
  // MRU 里的 app 按名次在前（最近激活的最前），没名次的按首现位置排后面。
  let input = [window(pid: 1, id: 10), window(pid: 2, id: 20), window(pid: 3, id: 30),
               window(pid: 2, id: 21)]
  #expect(pids(WindowCache.sort(input, byMRU: [2])) == [2, 2, 1, 3])
  #expect(pids(WindowCache.sort(input, byMRU: [2, 3])) == [2, 2, 3, 1])
}

@Test func windowsWithinAnAppKeepTheWindowListOrder() {
  // app 内保持 CGWindowList 的 front-to-back 顺序（`sorted` 本身不保证稳定，
  // 靠原下标定序 —— 这条测试就是那个保证）。
  let input = [window(pid: 1, id: 13), window(pid: 1, id: 11), window(pid: 1, id: 12)]
  #expect(WindowCache.sort(input, byMRU: []).map(\.windowID) == [13, 11, 12])
}

@Test func sortingNothingIsNothing() {
  #expect(WindowCache.sort([], byMRU: []).isEmpty)
  #expect(pids(WindowCache.sort([window(pid: 7, id: 70)], byMRU: [])) == [7])
}
