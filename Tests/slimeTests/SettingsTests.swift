import Foundation
import Testing

@testable import slime

// Review Focus 5：圆角被手动改成越界值（有人直接改 UserDefaults）时，
// 读的时候也要钳位 —— 不能因为存了个 9999 就让玻璃视图变形。

@Test func cornerRadiusIsClampedToTheSliderRange() {
  #expect(Settings.clampCornerRadius(-5) == 0)
  #expect(Settings.clampCornerRadius(100) == 40)
  #expect(Settings.clampCornerRadius(12) == 12)
  #expect(Settings.clampCornerRadius(0) == 0)
  #expect(Settings.clampCornerRadius(40) == 40)
}

@Test func nonFiniteCornerRadiusFallsBackToTheLowerBound() {
  #expect(Settings.clampCornerRadius(.nan) == 0)
  #expect(Settings.clampCornerRadius(.infinity) == 40)
  #expect(Settings.clampCornerRadius(-.infinity) == 0)
}

@Test func defaultsAreUsedWhenNothingWasEverSaved() throws {
  let suite = "slime.tests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let settings = Settings(defaults: defaults)
  #expect(settings.glassStyle == .regular)
  #expect(settings.glassTint == nil)
  #expect(settings.glassCornerRadius == 12)
}
