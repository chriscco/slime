import AppKit
import Testing
@testable import slime

@Test @MainActor func deniedAccessibilityOpensItsSettingsPaneOnEveryAttempt() {
  var requests = 0
  var destinations: [URL] = []
  for _ in 0..<2 {
    let opened = Permission.promptAccessibility(request: { options in
      requests += 1
      #expect((options as NSDictionary)["AXTrustedCheckOptionPrompt"] as? Bool == true)
      return false
    }, openSettings: { destinations.append($0); return true })
    #expect(opened)
  }
  #expect(requests == 2)
  #expect(destinations.map(\.absoluteString) == Array(repeating:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", count: 2))
}

@Test @MainActor func inaccessibleSettingsReportsFailureForManualFallback() {
  #expect(!Permission.promptAccessibility(request: { _ in false }, openSettings: { _ in false }))
}
