// @preconcurrency：kAXTrustedCheckOptionPrompt 是导入的全局 var（UnsafePointer），
// 严格并发下会被判成共享可变状态 —— 它是文档化的只读常量键，这里显式降级。
@preconcurrency import ApplicationServices
import Foundation

/// 辅助功能权限的检查与引导（spec §9）。
///
/// 本机坑（CLAUDE.md 第五条）：**授权后要重启 app 才生效** —— 对已在运行的
/// 进程，`AXIsProcessTrusted` 不会变。所以这里的流程是「引导 → 等用户授权
/// → 提示重启」，而不是原地重试。
enum Permission {
  /// 当前进程是否已取得辅助功能权限。
  static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

  /// 弹系统对话框引导用户去授权（对话框带「打开系统设置」）。
  static func promptAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  /// 引导之后轮询等用户授权。授权成功（或超时）调 `completion`，回主线程。
  ///
  /// 不自动重启：重启的触发留给用户（提示里说清），省掉自替换进程的时序问题。
  /// 用 Task.sleep 而不是 Timer：主 run loop 切模式（用户跟系统设置对话框
  /// 交互）时也不会停摆。
  static func waitUntilTrusted(
    timeout: TimeInterval = 120,
    completion: @escaping @MainActor (Bool) -> Void
  ) {
    Task { @MainActor in
      let deadline = Date().addingTimeInterval(timeout)
      while Date() < deadline {
        if isAccessibilityTrusted {
          completion(true)
          return
        }
        try? await Task.sleep(for: .seconds(1))
      }
      completion(false)
    }
  }
}
