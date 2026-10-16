import AppKit
import Sparkle

/// Sparkle owns downloading, signature checks, installation, and relaunch.
@MainActor
final class AppUpdater {
  var onChange: (() -> Void)?
  private let updater: SPUUpdater?
  private var observations: [NSKeyValueObservation] = []
  private(set) var isAvailable = false
  private(set) var errorMessage: String?

  init(bundle: Bundle = .main) {
    guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
          let url = URL(string: feed), url.scheme == "https", let host = url.host, !host.isEmpty,
          let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
          Data(base64Encoded: key)?.count == 32 else {
      updater = nil
      return
    }
    let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
    let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle,
      userDriver: driver, delegate: nil)
    self.updater = updater
    observations = [
      updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor [weak self] in self?.onChange?() }
      },
      updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor [weak self] in self?.onChange?() }
      },
    ]
  }

  func start() {
    guard let updater, !isAvailable else { return }
    do {
      try updater.start()
      isAvailable = true
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    onChange?()
  }

  var canCheckForUpdates: Bool { isAvailable && updater?.canCheckForUpdates == true }

  var automaticallyChecksForUpdates: Bool {
    get { isAvailable && updater?.automaticallyChecksForUpdates == true }
    set {
      guard isAvailable else { return }
      updater?.automaticallyChecksForUpdates = newValue
      onChange?()
    }
  }

  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    updater?.checkForUpdates()
  }
}
