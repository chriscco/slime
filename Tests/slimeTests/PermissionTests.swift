import Foundation
import Testing
@testable import slime

@Test @MainActor func accessibilityRequestLeavesTheSettingsChoiceToMacOS() {
  var requests = 0
  Permission.promptAccessibility(request: { options in
    requests += 1
    #expect((options as NSDictionary)["AXTrustedCheckOptionPrompt"] as? Bool == true)
    return false
  })
  #expect(requests == 1)
}

@Test @MainActor func missingAccessibilityPreservesEnablePreferenceAcrossRestarts() throws {
  let suite = "slime.permission-tests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  var requests = 0
  for _ in 0..<2 {
    let settings = Settings(defaults: defaults)
    #expect(settings.isEnabled)
    let app = AppDelegate(settings: settings)
    app.enable(isAccessibilityTrusted: { false }, promptAccessibility: { requests += 1 })
    #expect(settings.isEnabled, "Missing permission must not persist a user opt-out")
  }
  #expect(requests == 2)
}
