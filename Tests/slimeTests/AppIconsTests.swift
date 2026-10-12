import AppKit
import Testing

@testable import slime

// Review Focus 2：图标取不到时（bundleURL 为 nil 的 helper 进程、刚启动还没注册
// 的 app、进程已经退出）卡片不能空白，也不能崩。

@Test @MainActor func unknownPidFallsBackInsteadOfReturningNil() throws {
  // 一个几乎不可能存在的 pid。
  let ghost = Window(pid: 999_999, windowID: 1, appName: "Ghost", title: "x", isMinimized: false)
  let image = try #require(AppIcons.icon(for: ghost), "必须给一个通用图标，不能是 nil")
  #expect(image.size.width > 0)
}

@Test @MainActor func repeatedLookupsReturnTheSameInstance() throws {
  let ghost = Window(pid: 999_999, windowID: 1, appName: "Ghost", title: "x", isMinimized: false)
  let first = try #require(AppIcons.icon(for: ghost))
  let second = try #require(AppIcons.icon(for: ghost))
  #expect(first === second, "第二次应该是缓存命中，不是重新取")
}

@Test @MainActor func warmingAnEmptySnapshotIsHarmless() {
  AppIcons.warm([])
}
