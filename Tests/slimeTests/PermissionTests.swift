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
