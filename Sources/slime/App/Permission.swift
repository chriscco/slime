// @preconcurrency：kAXTrustedCheckOptionPrompt 是导入的全局 var（UnsafePointer），
// 严格并发下会被判成共享可变状态 —— 它是文档化的只读常量键，这里显式降级。
@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// 辅助功能权限的检查与引导（spec §9）。
///
/// 本机坑（CLAUDE.md 第五条）：**授权后要重启 app 才生效** —— 对已在运行的
/// 进程，`AXIsProcessTrusted` 不会变。所以这里的流程是「引导 → 等用户授权
/// → 提示重启」，而不是原地重试。
enum Permission {
  /// 当前进程是否已取得辅助功能权限。
  static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

  /// Register the permission request, then open its pane even if macOS suppresses repeat prompts.
  @MainActor @discardableResult
  static func promptAccessibility(
    request: (CFDictionary) -> Bool = { AXIsProcessTrustedWithOptions($0) },
    openSettings: (URL) -> Bool = { NSWorkspace.shared.open($0) }
  ) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      as CFDictionary
    _ = request(options)
    return openSettings(URL(string:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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

  /// 屏幕录制是第二项 TCC（spec §6）：和辅助功能**同性质** —— 绑代码签名
  /// （CLAUDE.md 第五条）、授权后要重启 slime 才生效。**没它 slime 照常可用**，
  /// 只是卡片退回 app 图标。这条降级是硬要求，不是「最好能」。
  static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

  /// 触发系统弹窗并返回结果。授权对运行中的进程通常还不生效 —— 只能靠文案说清。
  @discardableResult
  static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }
}
