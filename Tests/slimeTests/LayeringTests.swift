import Foundation
import Testing

@testable import slime

/// Core/ 是纯逻辑层：不许 import AppKit / CoreGraphics / ApplicationServices
/// （CLAUDE.md 第六条）。这条规则靠人记是记不住的，让测试来记 ——
/// Trigger 一旦能 import AppKit，就会有人顺手在里面摸 NSEvent，
/// 然后「吞掉不该吞的按键 → 全系统键盘挂掉」那个风险就再也没法在单测里穷举了。
@Test func coreNeverImportsSystemFrameworks() throws {
  let core = URL(fileURLWithPath: #filePath)  // Tests/slimeTests/LayeringTests.swift
    .deletingLastPathComponent()  // Tests/slimeTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // 仓库根
    .appendingPathComponent("Sources/slime/Core")

  let files = try FileManager.default.contentsOfDirectory(atPath: core.path)
    .filter { $0.hasSuffix(".swift") }
  #expect(!files.isEmpty, "找不到 Core/ 的源文件 —— 路径推导坏了，这个测试就成了摆设")

  for file in files {
    let source = try String(contentsOf: core.appendingPathComponent(file), encoding: .utf8)
    for framework in ["import AppKit", "import CoreGraphics", "import ApplicationServices"] {
      #expect(!source.contains(framework), "\(file) 里出现了 \(framework)")
    }
  }
}
