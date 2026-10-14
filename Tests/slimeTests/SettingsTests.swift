import AppKit
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
  #expect(settings.glassStrength == Settings.defaultGlassStrength)
  #expect(settings.highlightColor == Settings.defaultHighlightColor)
  #expect(settings.glassCornerRadius == 20)
}

@Test func glassStrengthIsClampedToZeroThroughOne() {
  // 同圆角：值可能是旧版本写的、或者被人手动改过。0 = 完全看不到背后，
  // 1 = 完全透明（spec §2 第 7 条）。
  #expect(Settings.clampStrength(-0.5) == 0)
  #expect(Settings.clampStrength(2) == 1)
  #expect(Settings.clampStrength(0.5) == 0.5)
  #expect(Settings.clampStrength(.nan) == 0)
  #expect(Settings.clampStrength(.infinity) == 1)
  #expect(Settings.clampStrength(-.infinity) == 0)
}

@Test func defaultHighlightColorIsSlimeGreen() throws {
  let srgb = try #require(Settings.defaultHighlightColor.usingColorSpace(.sRGB))
  #expect(abs(srgb.redComponent - 150.0 / 255) < 0.0001)
  #expect(abs(srgb.greenComponent - 215.0 / 255) < 0.0001)
  #expect(abs(srgb.blueComponent - 106.0 / 255) < 0.0001)
}

@Test func accentMigrationResetsOldColorsOnlyOnce() throws {
  let suite = "slime.tests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(try NSKeyedArchiver.archivedData(withRootObject: NSColor.orange,
    requiringSecureCoding: true), forKey: "highlight.color")
  let migrated = Settings(defaults: defaults)
  #expect(migrated.highlightColor == Settings.defaultHighlightColor)
  migrated.highlightColor = .purple
  #expect(Settings(defaults: defaults).highlightColor == .purple)
}

@Test func generalSettingsDefaultToEnabledUngroupedAndEnglishAndPersist() throws {
  let suite = "slime.tests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  #expect(settings.isEnabled)
  #expect(!settings.groupByApp)
  #expect(settings.language == .english)
  #expect(settings.text("Settings", "设置") == "Settings")
  settings.isEnabled = false
  settings.groupByApp = true
  settings.language = .chinese
  let reloaded = Settings(defaults: defaults)
  #expect(!reloaded.isEnabled)
  #expect(reloaded.groupByApp)
  #expect(reloaded.text("Settings", "设置") == "设置")
  defaults.set("unsupported", forKey: "language")
  #expect(settings.language == .english)
}
