import AppKit
import ApplicationServices
import Testing
@testable import slime

private func w(_ id: UInt32, _ pid: pid_t = 10) -> Window {
  Window(pid: pid, windowID: id, appName: "App", title: "same", isMinimized: false)
}
@Test @MainActor func focusPromotesIndividualWindowsAndKeepsCurrentFirst() {
  let cache = WindowCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  cache.apply([w(1), w(2, 20), w(3)], frontWindowID: 1, known: [:], generation: 0)
  cache.noteActivated(w(3))
  #expect(cache.snapshot.map(\.windowID) == [3, 1, 2])
  cache.noteActivated(w(2, 20))
  #expect(cache.snapshot.map(\.windowID) == [2, 3, 1])
}
@Test func ambiguousAXMatchNeverChoosesFirstWindow() {
  let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
  let entries = (0..<2).map { _ in AXWindows.Entry(element: AXUIElementCreateApplication(10), frame: frame, title: "same", subrole: kAXStandardWindowSubrole, minimized: false) }
  #expect(AXWindows.match(bounds: frame, title: "same", in: entries) == nil)
}
@Test func nativeIdentityWinsOverChangedTitlesAndIdenticalFrames() {
  let a = AXUIElementCreateApplication(10)
  let b = AXUIElementCreateApplication(20)
  let entries = [a, b].map { AXWindows.Entry(element: $0, frame: .zero, title: "same", subrole: kAXStandardWindowSubrole, minimized: false) }
  #expect(AXWindows.match(bounds: .zero, title: "old", in: entries, identity: b).map { CFEqual($0.element, b) } == true)
}
extension PanelAndThumbnailTests {
@Test @MainActor func panelInitiallySelectsPreviousIdentityAndFreezesSessionOrder() {
  _ = NSApplication.shared
  let settings = Settings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  settings.groupByApp = true
  let panel = PanelController(settings: settings)
  panel.setWindows([w(1), w(2, 20), w(3)])
  panel.handle(state: .lingering(query: "", selection: 0), effects: [.showPanel(.opt)])
  #expect(panel.rows.map(\.windowID) == [1, 3, 2])
  #expect(panel.rows[panel.selection].windowID == 2)
  panel.setWindows([w(2, 20), w(3), w(1), w(4)])
  #expect(panel.rows.map(\.windowID) == [1, 3, 2, 4])
  #expect(panel.rows[panel.selection].windowID == 2)
  panel.dismiss()
}
}
extension PanelAndThumbnailTests {
@Test @MainActor func activationFallbackDoesNotReportAnExactWindow() async {
  var applications: [pid_t] = []
  let result = await WindowActivator.activate(w(1), target: nil, request: AXRequest(seconds: 0.2), activateApp: { applications.append($0); return true }, frontmostPID: { applications.last }, monitorInput: { _ in {} })
  #expect(result == .application)
  #expect(applications == [10])
}
}

extension PanelAndThumbnailTests {
@Test @MainActor func cancelledActivationDoesNothing() async {
  let request = AXRequest(); request.cancel()
  let result = await WindowActivator.activate(w(1), target: nil, request: request, activateApp: { _ in Issue.record("cancelled activation reached app"); return true }, monitorInput: { _ in {} })
  #expect(result == .cancelled)
}
}

@Test @MainActor func focusEvidenceUpdatesTitleWithoutEnumerationAndRejectsOtherPID() {
  let cache = WindowCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  cache.apply([w(1), w(2)], frontWindowID: 1, known: [:], generation: 0)
  cache.noteFocused(windowID: 2, pid: 99, title: "wrong")
  #expect(cache.snapshot[0].windowID == 1)
  cache.noteFocused(windowID: 2, pid: 10, title: "fresh tab")
  #expect(cache.snapshot[0].windowID == 2)
  #expect(Search.rank(cache.snapshot, query: "fresh").map(\.windowID) == [2])
}
@Test func missingCachedIdentityCannotBeReboundToSameTitleSibling() {
  let old = AXUIElementCreateApplication(10)
  let other = AXUIElementCreateApplication(20)
  let entry = AXWindows.Entry(element: other, frame: .zero, title: "same", subrole: kAXStandardWindowSubrole, minimized: false)
  #expect(AXWindows.match(bounds: .zero, title: "same", in: [entry], identity: old) == nil)
}
private final class FocusReadCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  var count: Int { lock.withLock { value } }
  func read() -> (UInt32?, String?) { lock.withLock { value += 1 }; return (1, "fresh") }
}
@Test @MainActor func foregroundEventsCoalesceAndStopCancelsPendingReads() async throws {
  let counter = FocusReadCounter()
  let observer = ForegroundObserver(read: { _, _, _ in counter.read() })
  observer.watch(-12345)
  for _ in 0..<100 where counter.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(counter.count == 1)
  for _ in 0..<30 { observer.signal() }
  for _ in 0..<100 where counter.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(counter.count == 2)
  observer.signal()
  observer.stop()
  try await Task.sleep(for: .milliseconds(100))
  #expect(counter.count == 2)
}
private actor ActivationGate {
  var started = false
  private var continuation: CheckedContinuation<Bool, Never>?
  func raise() async -> Bool { started = true; return await withCheckedContinuation { continuation = $0 } }
  func finish() { continuation?.resume(returning: true); continuation = nil }
}
extension PanelAndThumbnailTests {
@Test @MainActor func overlappingFallbackRestoresLatestAppAfterOldRaiseWithoutPromotingOldTarget() async throws {
  let gate = ActivationGate()
  var applications: [pid_t] = []
  let firstRequest = AXRequest(seconds: 2)
  let first = Task { await WindowActivator.activate(w(1), target: NativeWindowTarget(pid: 10, windowID: 1, element: AXUIElementCreateApplication(10)), request: firstRequest, activateApp: { applications.append($0); return true }, frontmostPID: { applications.last }, monitorInput: { _ in {} }, raise: { _, _ in await gate.raise() }) }
  for _ in 0..<100 where !(await gate.started) { try await Task.sleep(for: .milliseconds(5)) }
  firstRequest.cancel()
  let second = Task { await WindowActivator.activate(w(2, 20), target: nil, request: AXRequest(seconds: 2), activateApp: { applications.append($0); return true }, frontmostPID: { applications.last }, monitorInput: { _ in {} }) }
  for _ in 0..<100 where applications.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
  #expect(applications == [10, 20])
  await gate.finish()
  #expect(await first.value == .cancelled)
  #expect(await second.value == .application)
  #expect(applications == [10, 20, 20])
}
}

@Test @MainActor func identicalFocusEvidenceDoesNotPublishOrInvalidateRefresh() {
  let cache = WindowCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  cache.apply([w(1)], frontWindowID: 1, known: [:], generation: 0)
  var changes = 0
  cache.onChange = { _ in changes += 1 }
  cache.noteFocused(windowID: 1, pid: 10, title: "same")
  #expect(changes == 0)
  cache.apply([w(1), w(2)], frontWindowID: 1, known: [:], generation: 0)
  #expect(cache.snapshot.count == 2)
}
@Test func staleCGNameDoesNotReplaceAnAXVerifiedTitleWhenAXListOmitsWindow() {
  let remembered = KnownWindow(appName: "Chrome", title: "fresh tab", minimized: false, axVerified: true)
  let result = WindowEnumerator.select([
    WindowCandidate(windowID: 1, pid: 10, appName: "Chrome", onscreen: false, matched: nil,
      helper: false, cgTitle: "old tab", axAvailable: true, appHasWindows: true)
  ], known: [1: remembered])
  #expect(result.windows.first?.title == "fresh tab")
}
extension PanelAndThumbnailTests {
@Test @MainActor func exactActivationUsesOneMaintainedTargetOperation() async {
  let counter = FocusReadCounter()
  let target = NativeWindowTarget(pid: 10, windowID: 1, element: AXUIElementCreateApplication(10))
  let result = await WindowActivator.activate(w(1), target: target, request: AXRequest(seconds: 2), activateApp: { _ in true }, frontmostPID: { 10 }, monitorInput: { _ in {} }, raise: { target, _ in
    #expect(target.pid == 10 && target.windowID == 1)
    _ = counter.read()
    return true
  })
  #expect(result == .exact)
  #expect(counter.count == 1)
}
@Test @MainActor func mismatchedTargetNeverReachesNativeRaise() async {
  for target in [NativeWindowTarget(pid: 20, windowID: 1, element: AXUIElementCreateApplication(20)), NativeWindowTarget(pid: 10, windowID: 2, element: AXUIElementCreateApplication(10))] {
    let result = await WindowActivator.activate(w(1), target: target, request: AXRequest(seconds: 2), activateApp: { _ in true }, frontmostPID: { 10 }, monitorInput: { _ in {} }, raise: { _, _ in Issue.record("mismatched target raised"); return true })
    #expect(result == .application)
  }
}
@Test @MainActor func oneWindowPanelSelectsItAndSearchKeepsRelevanceWhenGrouped() {
  _ = NSApplication.shared
  let settings = Settings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  settings.groupByApp = true
  let panel = PanelController(settings: settings)
  panel.setWindows([w(1)])
  panel.handle(state: .lingering(query: "", selection: 0), effects: [.showPanel(.opt)])
  #expect(panel.rows[panel.selection].windowID == 1)
  let fresh = Window(pid: 20, windowID: 2, appName: "App", title: "z", isMinimized: false)
  panel.setWindows([fresh, w(1)])
  panel.handle(state: .lingering(query: "z", selection: 0), effects: [.appendQuery("z")])
  #expect(panel.rows.map(\.windowID) == [2])
  panel.setWindows([w(1)])
  #expect(panel.rows.isEmpty)
  panel.dismiss()
}
}
@Test func partialAXSnapshotCannotBeClaimedByAnotherSameFrameCGWindow() {
  #expect(!WindowEnumerator.canClaim(windowID: 2, frameMatches: [1, 2], titleMatches: [1], visibleFrameMatches: [1, 2]))
  #expect(WindowEnumerator.canClaim(windowID: 1, frameMatches: [1, 2], titleMatches: [1], visibleFrameMatches: [1, 2]))
  #expect(!WindowEnumerator.canClaim(windowID: 2, frameMatches: [1, 2], titleMatches: [], visibleFrameMatches: [1]))
  #expect(WindowEnumerator.canClaim(windowID: 1, frameMatches: [1, 2], titleMatches: [], visibleFrameMatches: [1]))
}
extension PanelAndThumbnailTests {
@Test @MainActor func externalFocusWinsOverAnOverlappingSwitchCompletion() async throws {
  let gate = ActivationGate()
  var front: pid_t = 10
  var apps: [pid_t] = []
  let firstRequest = AXRequest(seconds: 2)
  let first = Task { await WindowActivator.activate(w(1), target: NativeWindowTarget(pid: 10, windowID: 1, element: AXUIElementCreateApplication(10)), request: firstRequest, activateApp: { apps.append($0); front = $0; return true }, frontmostPID: { front }, monitorInput: { _ in {} }, raise: { _, _ in await gate.raise() }) }
  for _ in 0..<100 where !(await gate.started) { try await Task.sleep(for: .milliseconds(5)) }
  firstRequest.cancel()
  let second = Task { await WindowActivator.activate(w(2, 20), target: nil, request: AXRequest(seconds: 2), activateApp: { apps.append($0); front = $0; return true }, frontmostPID: { front }, monitorInput: { _ in {} }) }
  for _ in 0..<100 where apps.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
  front = 30
  await gate.finish()
  #expect(await first.value == .cancelled)
  #expect(await second.value == .cancelled)
  #expect(apps == [10, 20])
}
}
extension PanelAndThumbnailTests {
@Test @MainActor func externalActivationEventPreventsRestorationEvenIfOldRaiseReturnsToItsApp() async throws {
  let gate = ActivationGate()
  var front: pid_t = 10
  var apps: [pid_t] = []
  let firstRequest = AXRequest(seconds: 2)
  let first = Task { await WindowActivator.activate(w(1), target: NativeWindowTarget(pid: 10, windowID: 1, element: AXUIElementCreateApplication(10)), request: firstRequest, activateApp: { apps.append($0); front = $0; return true }, frontmostPID: { front }, monitorInput: { _ in {} }, raise: { _, _ in await gate.raise() }) }
  for _ in 0..<100 where !(await gate.started) { try await Task.sleep(for: .milliseconds(5)) }
  firstRequest.cancel()
  let secondRequest = AXRequest(seconds: 2)
  let second = Task { await WindowActivator.activate(w(2, 20), target: nil, request: secondRequest, activateApp: { apps.append($0); front = $0; return true }, frontmostPID: { front }, monitorInput: { _ in {} }) }
  for _ in 0..<100 where apps.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
  front = 30
  NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
    userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
  #expect(secondRequest.isCancelled)
  front = 10 // The older in-flight raise can itself bring its app forward.
  await gate.finish()
  #expect(await first.value == .cancelled)
  #expect(await second.value == .cancelled)
  #expect(apps == [10, 20])
}
}
extension PanelAndThumbnailTests {
@Test @MainActor func newInputWithinTargetAppCancelsQueuedRaiseAndRemovesMonitor() async throws {
  let gate = ActivationGate()
  var apps: [pid_t] = []
  var input: (() -> Void)?
  var removed = false
  let firstRequest = AXRequest(seconds: 2)
  let first = Task { await WindowActivator.activate(w(1), target: NativeWindowTarget(pid: 10, windowID: 1, element: AXUIElementCreateApplication(10)), request: firstRequest, activateApp: { apps.append($0); return true }, frontmostPID: { apps.last }, monitorInput: { _ in {} }, raise: { _, _ in await gate.raise() }) }
  for _ in 0..<100 where !(await gate.started) { try await Task.sleep(for: .milliseconds(5)) }
  firstRequest.cancel()
  let secondRequest = AXRequest(seconds: 2)
  let second = Task { await WindowActivator.activate(w(2, 20), target: NativeWindowTarget(pid: 20, windowID: 2, element: AXUIElementCreateApplication(20)), request: secondRequest, activateApp: { apps.append($0); return true }, frontmostPID: { apps.last }, monitorInput: { request in
    input = { request.cancel() }
    return { removed = true }
  }, raise: { _, _ in Issue.record("new input must cancel B1 raise"); return true }) }
  for _ in 0..<100 where input == nil { try await Task.sleep(for: .milliseconds(5)) }
  input?() // The user clicks B2; the application PID remains B.
  #expect(secondRequest.isCancelled)
  await gate.finish()
  #expect(await first.value == .cancelled)
  #expect(await second.value == .cancelled)
  #expect(apps == [10, 20])
  #expect(removed)
}
}
