import AppKit
import Testing
@testable import slime

@Test @MainActor func settingsLanguageControlPersistsAndRebuildsTheWindow() throws {
  _ = NSApplication.shared
  let suite = "slime.settings-ui.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = SettingsWindowController(settings: settings)
  let window = controller.makeWindow()
  #expect(window.title == "slime Settings")
  let popup = try #require(descendants(window.contentView!).compactMap { $0 as? NSPopUpButton }.first)
  popup.selectItem(at: 1)
  let action = try #require(popup.action)
  NSApp.sendAction(action, to: popup.target, from: popup)
  #expect(settings.language == .chinese)
  #expect(window.title == "slime 设置")
  #expect(descendants(window.contentView!).compactMap { $0 as? NSButton }.contains { $0.title == "关于" })
}

@MainActor private func descendants(_ view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(descendants)
}

@Test @MainActor func generalSwitchesPersistAndNotifyTheApp() throws {
  _ = NSApplication.shared
  let suite = "slime.settings-switches.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = SettingsWindowController(settings: settings)
  var changes = 0
  controller.onChange = { changes += 1 }
  let window = controller.makeWindow()
  let switches = descendants(window.contentView!).compactMap { $0 as? NSSwitch }
  let enabled = try #require(switches.first { $0.accessibilityLabel() == "Enable slime" })
  enabled.state = .off
  NSApp.sendAction(try #require(enabled.action), to: enabled.target, from: enabled)
  let group = try #require(switches.first { $0.accessibilityLabel() == "Group windows by app" })
  group.state = .on
  NSApp.sendAction(try #require(group.action), to: group.target, from: group)
  #expect(!settings.isEnabled)
  #expect(settings.groupByApp)
  #expect(changes == 2)
}
