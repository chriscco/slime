import AppKit
import Testing
@testable import slime

@Test @MainActor func commandWClosesSettingsFromEverySectionWithoutQuitting() throws {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  defer { window.orderOut(nil) }
  for section in 0..<4 {
    let button = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
      .first { $0.tag == section && $0.action == NSSelectorFromString("selectSection:") })
    button.performClick(nil)
    window.orderFront(nil)
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
    #expect(window.performKeyEquivalent(with: event))
    #expect(!window.isVisible)
  }
}

@Test @MainActor func aboutFitsTheFullRoundedBannerAboveVersionAndLinks() throws {
  _ = NSApplication.shared
  let artwork = NSImage(size: NSSize(width: 2172, height: 724))
  let controller = SettingsWindowController(banner: artwork)
  let window = controller.makeWindow()
  let about = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.tag == 3 && $0.action != nil })
  about.performClick(nil)
  window.contentView?.layoutSubtreeIfNeeded()
  let banner = try #require(descendants(window.contentView!).compactMap { $0 as? NSImageView }.first)
  #expect(banner.image === artwork)
  #expect(banner.imageScaling == .scaleProportionallyUpOrDown)
  #expect(banner.layer?.cornerRadius == 12)
  #expect(banner.layer?.masksToBounds == true)
  #expect(banner.accessibilityLabel() == "slime")
  #expect(abs(banner.frame.width / banner.frame.height - 3) < 0.01)
  #expect(window.contentView!.frame.width == 720, "Artwork must not expand the settings window")
  #expect(banner.frame.width <= 490)
  let labels = descendants(window.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue)
  #expect(!labels.contains("slime"), "The banner already includes the name")
  #expect(labels.contains { $0.hasPrefix("Version ") })
}

@Test @MainActor func aboutUpdateControlsReflectAvailabilityAndPersistOptIn() throws {
  _ = NSApplication.shared
  let (url, bundle) = try updateTestBundle()
  defer {
    UserDefaults.standard.removePersistentDomain(forName: bundle.bundleIdentifier!)
    try? FileManager.default.removeItem(at: url)
  }
  let updater = AppUpdater(bundle: bundle)
  updater.start()
  let controller = SettingsWindowController(updater: updater)
  let window = controller.makeWindow()
  let about = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.tag == 3 && $0.action != nil })
  about.performClick(nil)
  let check = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.title == "Check for Updates…" })
  #expect(check.isEnabled)
  let automatic = try #require(descendants(window.contentView!).compactMap { $0 as? NSSwitch }
    .first { $0.accessibilityLabel() == "Automatically check" })
  #expect(automatic.state == .off)
  automatic.state = .on
  NSApp.sendAction(try #require(automatic.action), to: automatic.target, from: automatic)
  #expect(updater.automaticallyChecksForUpdates)
  automatic.state = .off
  NSApp.sendAction(try #require(automatic.action), to: automatic.target, from: automatic)
  #expect(!updater.automaticallyChecksForUpdates)
  #expect(automatic.window === window, "Changing update preferences must not rebuild focused controls")
}

@Test @MainActor func unconfiguredBuildsExplainWhyUpdatesAreDisabled() throws {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  let about = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.tag == 3 && $0.action != nil })
  about.performClick(nil)
  let check = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.title == "Check for Updates…" })
  #expect(!check.isEnabled)
  #expect(descendants(window.contentView!).compactMap { $0 as? NSTextField }
    .contains { $0.stringValue.contains("Updates are not configured") })
}

@Test @MainActor func settingsYieldsWindowLevelToUpdateDialogs() {
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
  #expect(window.level == .normal, "Sparkle dialogs must not sit behind floating settings")
  controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
  #expect(window.level == .floating)
}

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

@Test @MainActor func aboutFallsBackToTheNameWhenArtworkIsMissing() throws {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  let about = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.tag == 3 && $0.action != nil })
  NSApp.sendAction(try #require(about.action), to: about.target, from: about)
  let labels = descendants(window.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue)
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


@Test @MainActor func appearanceSlidersShowLivePercentagesWithoutRebuilding() throws {
  _ = NSApplication.shared
  let suite = "slime.slider-percent.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = SettingsWindowController(settings: settings, supportsGlass: true)
  var changes = 0
  controller.onChange = { changes += 1 }
  let window = controller.makeWindow()
  let appearance = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Appearance" })
  appearance.performClick(nil)
  let sliders = descendants(window.contentView!).compactMap { $0 as? NSSlider }
  for (name, initial, maximum) in [("Glass strength", "13%", 1.0), ("Panel corners", "50%", 40.0)] {
    let slider = try #require(sliders.first { $0.accessibilityLabel() == name })
    let value = try #require(slider.superview?.subviews.compactMap { $0 as? NSTextField }.first)
    #expect(value.stringValue == initial)
    #expect(slider.isContinuous)
    for fraction in [0.0, 0.25, 1.0] {
      slider.doubleValue = maximum * fraction
      NSApp.sendAction(try #require(slider.action), to: slider.target, from: slider)
      #expect(value.stringValue == "\(Int(fraction * 100))%")
      #expect(slider.window === window)
      #expect(name == "Glass strength" ? settings.glassStrength == fraction : settings.glassCornerRadius == maximum * fraction)
    }
  }
  #expect(changes == 6)
  #expect(Settings(defaults: defaults).glassStrength == 1)
}

@Test(arguments: [false, true]) @MainActor
func materialControlsFollowCapabilityAndPreserveGlassValues(supportsGlass: Bool) throws {
  _ = NSApplication.shared
  let suite = "slime.material-ui.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  settings.glassStrength = 0.65
  settings.glassStyle = .clear
  let controller = SettingsWindowController(settings: settings, supportsGlass: supportsGlass)
  let window = controller.makeWindow()
  let appearance = try #require(descendants(window.contentView!).compactMap { $0 as? NSButton }
    .first { $0.title == "Appearance" })
  appearance.performClick(nil)
  let selectors = descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }
  let material = selectors.first { $0.accessibilityLabel() == "Background material" }
  #expect((material != nil) == supportsGlass)
  #expect(defaults.object(forKey: "panel.material") == nil)
  func hasStrength() -> Bool {
    descendants(window.contentView!).compactMap { $0 as? NSSlider }
      .contains { $0.accessibilityLabel() == "Glass strength" }
  }
  #expect(hasStrength() == supportsGlass)
  if let material {
    var changes = 0
    controller.onChange = { changes += 1 }
    material.selectedSegment = 1
    NSApp.sendAction(try #require(material.action), to: material.target, from: material)
    #expect(settings.panelMaterial == .solid)
    #expect(!hasStrength())
    let replacement = try #require(descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }
      .first { $0.accessibilityLabel() == "Background material" })
    replacement.selectedSegment = 0
    NSApp.sendAction(try #require(replacement.action), to: replacement.target, from: replacement)
    #expect(settings.panelMaterial == .glass)
    #expect(hasStrength())
    #expect(changes == 2)
  } else {
    #expect(descendants(window.contentView!).compactMap { $0 as? NSTextField }
      .contains { $0.stringValue.contains("requires macOS 26") })
  }
  #expect(settings.glassStrength == 0.65)
  #expect(settings.glassStyle == .clear)
  #expect(descendants(window.contentView!).contains { $0 is NSColorWell })
  #expect(descendants(window.contentView!).compactMap { $0 as? NSSlider }
    .contains { $0.accessibilityLabel() == "Panel corners" })
}

@Test @MainActor func settingsCannotCoverASystemPermissionPromptWhileStillKey() {
  _ = NSApplication.shared
  let controller = SettingsWindowController()
  let window = controller.makeWindow()
  defer { window.orderOut(nil) }
  window.orderFront(nil)
  #expect(window.isVisible)
  controller.hideForPermissionPrompt()
  #expect(!window.isVisible)
  controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
  #expect(!window.isVisible, "A delayed focus notification must not restore settings above the prompt")
  controller.show()
  #expect(window.isVisible, "The menu-bar Settings action must still reopen the window")
}
