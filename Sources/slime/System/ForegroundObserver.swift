import AppKit
import ApplicationServices

/// Only the foreground app is observed. Callbacks enqueue work; they never perform AX IPC.
@MainActor final class ForegroundObserver {
  private let read: (@Sendable (pid_t, [UInt32: NativeWindowTarget], AXRequest) -> (UInt32?, String?))?
  init(read: (@Sendable (pid_t, [UInt32: NativeWindowTarget], AXRequest) -> (UInt32?, String?))? = nil) {
    self.read = read
  }
  private var observer: ObserverHandle?
  private var generation = 0
  private var request: AXRequest?
  private var pending: Task<Void, Never>?
  private var reading = false
  private var dirty = false
  private var discover = false
  private var pid: pid_t?
  var targets: [UInt32: NativeWindowTarget] = [:]
  var onFocus: ((UInt32, pid_t, String?) -> Void)?
  var onUnknown: (() -> Void)?

  func watch(_ pid: pid_t) {
    guard self.pid != pid else { signal(); return }
    stop()
    self.pid = pid
    let generation = generation
    let request = AXRequest(seconds: 0.3)
    self.request = request
    let context = ObserverContext(owner: self)
    Task {
      let handle = await Task.detached {
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, pointer in
          guard let pointer else { return }
          let context = Unmanaged<ObserverContext>.fromOpaque(pointer).takeUnretainedValue()
          Task { @MainActor in context.owner?.signal() }
        }, &observer) == .success, let observer else { return Optional<ObserverHandle>.none }
        let app = AXUIElementCreateApplication(pid)
        let handle = ObserverHandle(observer: observer, app: app, context: context)
        for notification in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification, kAXTitleChangedNotification] {
          guard request.prepare(app) else { break }
          AXObserverAddNotification(observer, app, notification as CFString, Unmanaged.passUnretained(context).toOpaque())
        }
        return handle
      }.value
      guard self.generation == generation, !request.isCancelled else { return }
      self.observer = handle
      if let handle { CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(handle.observer), .commonModes) }
      self.signal()
    }
  }

  func stop() {
    generation += 1
    request?.cancel()
    pending?.cancel(); pending = nil
    if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .commonModes) }
    observer = nil
    pid = nil
    dirty = false
    discover = false
  }

  func signal(discover: Bool = true) {
    self.discover = self.discover || discover
    dirty = true
    guard pending == nil, !reading, pid != nil else { return }
    pending = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(40))
      guard !Task.isCancelled, let self else { return }
      self.pending = nil
      await self.readFocus()
    }
  }

  private func readFocus() async {
    guard let pid else { return }
    dirty = false; reading = true
    let discover = discover
    self.discover = false
    let generation = generation
    let targets = targets
    let handle = observer
    let read = read
    let request = AXRequest(seconds: 0.3)
    self.request = request
    let result = await Task.detached { () -> (UInt32?, String?) in
      if let read { return read(pid, targets, request) }
      let app = AXUIElementCreateApplication(pid)
      var value: CFTypeRef?
      guard request.copy(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
        let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, nil) }
      let focused = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
      // Title notifications are commonly sent by the window, not its application.
      handle?.observeWindow(focused, request: request)
      let matches = targets.values.filter { $0.pid == pid && CFEqual($0.element, focused) }
      guard matches.count == 1 else { return (nil, nil) }
      var title: CFTypeRef?
      _ = request.copy(focused, kAXTitleAttribute as CFString, &title)
      return (matches[0].windowID, title as? String)
    }.value
    reading = false
    guard self.generation == generation else { if dirty { signal(discover: false) }; return }
    if let id = result.0 { onFocus?(id, pid, result.1) } else if discover { onUnknown?() }
    if dirty { signal(discover: false) }
  }
}

private final class ObserverContext: @unchecked Sendable {
  @MainActor weak var owner: ForegroundObserver?
  @MainActor init(owner: ForegroundObserver) { self.owner = owner }
}

/// Accessed only by the observer's sequential background jobs; retained by each in-flight job.
private final class ObserverHandle: @unchecked Sendable {
  let observer: AXObserver
  let app: AXUIElement
  let context: ObserverContext
  private var window: AXUIElement?
  init(observer: AXObserver, app: AXUIElement, context: ObserverContext) {
    self.observer = observer; self.app = app; self.context = context
  }
  deinit {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    // In-flight jobs retain this handle; deinit transfers these detached resources only to cleanup.
    nonisolated(unsafe) let observer = observer
    nonisolated(unsafe) let app = app
    nonisolated(unsafe) let window = window
    let context = context
    DispatchQueue.global(qos: .utility).async {
      let request = AXRequest(seconds: 0.3)
      withExtendedLifetime(context) {
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification, kAXTitleChangedNotification] {
          guard request.prepare(app) else { break }
          AXObserverRemoveNotification(observer, app, name as CFString)
        }
        if let window {
          for name in [kAXTitleChangedNotification, kAXUIElementDestroyedNotification] {
            guard request.prepare(window) else { break }
            AXObserverRemoveNotification(observer, window, name as CFString)
          }
        }
      }
    }
  }
  func observeWindow(_ element: AXUIElement, request: AXRequest) {
    guard window.map({ CFEqual($0, element) }) != true else { return }
    if let window, request.prepare(window) {
      AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString)
      if request.prepare(window) { AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString) }
    }
    window = element
    for name in [kAXTitleChangedNotification, kAXUIElementDestroyedNotification] {
      guard request.prepare(element) else { return }
      AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(context).toOpaque())
    }
  }
}
