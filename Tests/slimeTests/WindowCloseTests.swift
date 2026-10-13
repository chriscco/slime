import ApplicationServices
import CoreGraphics
import Testing
@testable import slime

private func entry(_ frame: CGRect, title: String = "Document") -> AXWindows.Entry {
  AXWindows.Entry(element: AXUIElementCreateApplication(1), frame: frame, title: title,
    subrole: kAXStandardWindowSubrole, minimized: false)
}

@Test func closingRequiresOneToOneGeometryAndNeverFallsBackToAnAmbiguousTitle() {
  let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
  let target = WindowActivator.CloseCandidate(windowID: 1, bounds: frame, title: nil)
  let twin = WindowActivator.CloseCandidate(windowID: 2, bounds: frame, title: nil)
  #expect(WindowActivator.closeMatch(target: target, entries: [entry(frame)], candidates: [target]) == 0)
  #expect(WindowActivator.closeMatch(target: target, entries: [entry(frame), entry(frame)], candidates: [target]) == nil)
  #expect(WindowActivator.closeMatch(target: target, entries: [entry(frame)], candidates: [target, twin]) == nil)
  #expect(WindowActivator.closeMatch(target: target,
    entries: [entry(frame.offsetBy(dx: 100, dy: 0))], candidates: [target]) == nil)
}

@Test func stageManagerCloseRequiresAUniqueLiveTitleOnBothSides() {
  let strip = CGRect(x: -566, y: -581, width: 123, height: 112)
  let full = CGRect(x: -32, y: -900, width: 1249, height: 780)
  let target = WindowActivator.CloseCandidate(windowID: 305, bounds: strip, title: "ChatGPT")
  let ax = entry(full, title: "ChatGPT")
  #expect(WindowActivator.closeMatch(target: target, entries: [ax], candidates: [target]) == 0)
  let twin = WindowActivator.CloseCandidate(windowID: 306, bounds: full, title: "ChatGPT")
  #expect(WindowActivator.closeMatch(target: target, entries: [ax], candidates: [target, twin]) == nil)
  #expect(WindowActivator.closeMatch(target: target, entries: [ax, ax], candidates: [target]) == nil)
  #expect(WindowActivator.closeMatch(target: target,
    entries: [entry(full, title: "Another window")], candidates: [target]) == nil)
}

@Test func closingIgnoresOffDisplaySurfacesButKeepsStageManagerTiles() {
  let tile = CGRect(x: -566, y: -581, width: 123, height: 112)
  let offDisplay = CGRect(x: -1360, y: 255, width: 800, height: 600)
  let displays = [CGRect(x: 0, y: 0, width: 1470, height: 956),
                  CGRect(x: -582, y: -1080, width: 1920, height: 1080)]
  let raw: [[String: Any]] = [(UInt32(305), tile), (UInt32(9006), offDisplay)].map { id, frame in
    [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid_t(702),
     kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1.0,
     kCGWindowName as String: "ChatGPT", kCGWindowBounds as String: frame.dictionaryRepresentation]
  }
  let candidates = WindowActivator.closeCandidates(raw, pid: 702, displays: displays)
  #expect(candidates.map(\.windowID) == [305])
  #expect(WindowActivator.closeCandidates(raw, pid: 703, displays: displays).isEmpty)
  #expect(WindowActivator.closeCandidates(raw, pid: 702, displays: []).count == 2)
}
