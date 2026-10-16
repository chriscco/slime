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
  // Build with a macOS 26+ SDK; Liquid Glass is runtime-gated.
  platforms: [.macOS("15.0")],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
  ],
  targets: [
    .executableTarget(name: "slime", dependencies: [
      .product(name: "Sparkle", package: "Sparkle"),
    ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(
      name: "slimeTests",
      dependencies: ["slime"]
    ),
  ]
)
