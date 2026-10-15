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
  [view] + (view is NSButton ? [] : view.subviews.flatMap(descendants))
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
  #expect(labels.count == 2, "Labels: \(labels)")
  #expect(labels.contains("slime"))
  #expect(!descendants(window.contentView!).contains { $0 is NSVisualEffectView })
}

@Test @MainActor func accentChangesUpdateTheExistingSidebarWithoutReplacingTheColorWell() throws {
  _ = NSApplication.shared
  let suite = "slime.settings-accent.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let controller = SettingsWindowController(settings: Settings(defaults: defaults))
  let window = controller.makeWindow()
  let appearance = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.title == "Appearance" })
  NSApp.sendAction(try #require(appearance.action), to: appearance.target, from: appearance)
  let selected = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.title == "Appearance" })
  let well = try #require(descendants(window.contentView!).compactMap { $0 as? NSColorWell }.first)
  well.color = .systemPink
  NSApp.sendAction(try #require(well.action), to: well.target, from: well)
  #expect(selected.contentTintColor == .systemPink)
  #expect(well.window === window)
}

@Test @MainActor func backgroundPreviewsPersistSelectionAndKeepAllControlsReachable() throws {
  _ = NSApplication.shared
  let suite = "slime.theme-ui.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = SettingsWindowController(settings: settings)
  var changes = 0
  controller.onChange = { changes += 1 }
  let window = controller.makeWindow()
  let appearance = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Appearance" })
  NSApp.sendAction(try #require(appearance.action), to: appearance.target, from: appearance)
  let white = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.accessibilityLabel() == "White" })
  white.performClick(nil)
  #expect(defaults.string(forKey: "panel.background") == "white")
  #expect(white.state == .on)
  #expect(white.accessibilityValue() as? Int == 1)
  #expect(white.accessibilityRole() == .radioButton)
  #expect(changes == 1)
  #expect(white.window === window)
  let black = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.accessibilityLabel() == "Black" })
  #expect(black.state == .off)
  window.contentView?.layoutSubtreeIfNeeded()
  for button in descendants(window.contentView!).compactMap({ $0 as? PanelBackgroundButton }) {
    #expect(button.frame.height == 102)
  }
  let scroll = try #require(descendants(window.contentView!).compactMap { $0 as? NSScrollView }.first)
  let document = try #require(scroll.documentView)
  #expect(document.frame.height > scroll.contentSize.height)
  let lastSlider = try #require(descendants(document).compactMap { $0 as? NSSlider }
    .first { $0.accessibilityLabel() == "Panel corners" })
  let rect = document.convert(lastSlider.bounds, from: lastSlider)
  #expect(document.bounds.contains(rect))
  document.scrollToVisible(rect)
  #expect(scroll.documentVisibleRect.intersects(rect))
}

@Test @MainActor func backgroundPreviewAcceptsClicksAcrossTheWholeCard() throws {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  let appearance = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Appearance" })
  appearance.performClick(nil)
  window.contentView?.layoutSubtreeIfNeeded()
  let button = try #require(descendants(window.contentView!).compactMap { $0 as? PanelBackgroundButton }.first)
  for point in [NSPoint(x: 20, y: 20), NSPoint(x: button.bounds.midX, y: button.bounds.midY), NSPoint(x: 20, y: 85)] {
    let location = button.convert(point, to: nil)
    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: location,
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
    let hit = try #require(button.cell?.hitTest(for: event, in: button.bounds, of: button))
    #expect(hit.contains(.trackableArea), "Click at \(point) returned \(hit)")
    #expect(window.contentView?.hitTest(window.contentView!.convert(location, from: nil)) === button)
  }
}
