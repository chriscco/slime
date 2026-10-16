import AppKit
import Testing
@testable import slime

@MainActor func updateTestBundle(overrides: [String: Any] = [:]) throws -> (URL, Bundle) {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("slime-updater-\(UUID().uuidString).app")
  try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
  var info: [String: Any] = [
    "CFBundleIdentifier": "test.slime.updates.\(UUID().uuidString)", "CFBundleName": "slime test",
    "CFBundleVersion": "8", "CFBundleShortVersionString": "0.0.8", "CFBundlePackageType": "APPL",
    "SUFeedURL": "https://example.invalid/appcast.xml",
    "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
    "SUEnableAutomaticChecks": false, "SUAllowsAutomaticUpdates": false,
    "SUAutomaticallyUpdate": false, "SUSendProfileInfo": false,
    "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
  ]
  info.merge(overrides) { _, replacement in replacement }
  try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: url.appendingPathComponent("Contents/Info.plist"))
  return (url, try #require(Bundle(url: url)))
}

@Test @MainActor func updaterRejectsMissingKeysAndInsecureFeedsWithoutStarting() throws {
  _ = NSApplication.shared
  for overrides: [String: Any] in [
    ["SUPublicEDKey": ""], ["SUPublicEDKey": "not a key"],
    ["SUFeedURL": "http://example.invalid/appcast.xml"],
    ["SUFeedURL": "https:///appcast.xml"],
  ] {
    let (url, bundle) = try updateTestBundle(overrides: overrides)
    defer { try? FileManager.default.removeItem(at: url) }
    let updater = AppUpdater(bundle: bundle)
    updater.start()
    #expect(!updater.isAvailable)
    #expect(!updater.canCheckForUpdates)
    updater.automaticallyChecksForUpdates = true
    #expect(!updater.automaticallyChecksForUpdates)
    updater.checkForUpdates() // Unconfigured development builds must not launch a dialog/network request.
  }
}

@Test @MainActor func updaterStartsOnceAndPersistsOnlyExplicitAutomaticCheckChoices() throws {
  _ = NSApplication.shared
  let (url, bundle) = try updateTestBundle()
  let defaults = try #require(UserDefaults(suiteName: try #require(bundle.bundleIdentifier)))
  defer {
    defaults.removePersistentDomain(forName: bundle.bundleIdentifier!)
    try? FileManager.default.removeItem(at: url)
  }
  let updater = AppUpdater(bundle: bundle)
  updater.start()
  updater.start()
  #expect(updater.isAvailable)
  #expect(updater.canCheckForUpdates)
  #expect(!updater.automaticallyChecksForUpdates)
  updater.automaticallyChecksForUpdates = true
  #expect(defaults.bool(forKey: "SUEnableAutomaticChecks"))
  updater.automaticallyChecksForUpdates = false
  #expect(!defaults.bool(forKey: "SUEnableAutomaticChecks"))
  #expect(!defaults.bool(forKey: "SUAutomaticallyUpdate"))
}
