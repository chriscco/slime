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

@Test @MainActor func settingsStayAboveOrdinaryWindowsOnTheCurrentSpace() {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  #expect(window.level == .floating)
  #expect(window.collectionBehavior.contains(.moveToActiveSpace))
  #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
}

@Test @MainActor func aboutContainsOnlyNameVersionAndRepository() throws {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  let about = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.tag == 3 && $0.action != nil })
  NSApp.sendAction(try #require(about.action), to: about.target, from: about)
  let labels = descendants(window.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue)
  #expect(labels.count == 2)
  #expect(labels.contains("slime"))
  #expect(!descendants(window.contentView!).contains { $0 is NSVisualEffectView })
}
