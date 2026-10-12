// swift-tools-version:6.0
// Swift 6 语言模式（tools 6.0 的默认），测试用 swift-testing（`import Testing`）。
//
// 为什么不用 XCTest：本机只有 CommandLineTools。XCTest 的模块不在 toolchain 里，
// 而 Swift 6 工具链自带 swift-testing —— 测试就能不装完整 Xcode 跑起来。
// 本机补 Testing 搜索路径的活见 scripts/test（那里写了为什么不能放进本文件）。
//
// shortcut: Swift 6 严格并发从第一天开始用；万一某处 AppKit 代码只能靠
// @unchecked Sendable 硬压，就地注释说明，别顺手关掉整个 target 的检查

import PackageDescription

let package = Package(
  name: "slime",
  // macOS 26 是 NSGlassEffectView 的门槛（spec §4）。
  // 不做 NSVisualEffectView 兜底分支：CI 和开发机都在 26 以上，
  // 回退路径是一段永远没人能执行的死代码。
  //
  // 字符串形式而不是 .v26：manifest 是 tools-version 6.0，而 .v26 这个
  // 枚举值要 6.2 才有（实测 `error: 'v26' is unavailable`）。⚠️ 跟编译器
  // 版本无关 —— PackageDescription 的 API 面是按 manifest 里声明的
  // tools-version 选的，所以 CI（Swift 6.3.3）用 tools 6.0 一样编不过。
  platforms: [.macOS("26.0")],
  targets: [
    .executableTarget(name: "slime"),
    .testTarget(
      name: "slimeTests",
      dependencies: ["slime"]
    ),
  ]
)
