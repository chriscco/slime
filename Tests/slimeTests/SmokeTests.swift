import Testing

@testable import slime

// 冒烟测试：证明测试链路本身是通的 —— 本机（CommandLineTools）和 CI（完整
// Xcode）都要能跑。真正的行为测试从 Core/ 的 Search 和 Trigger 开始。
@Test func packageBuilds() {
  #expect(Bool(true))
}
