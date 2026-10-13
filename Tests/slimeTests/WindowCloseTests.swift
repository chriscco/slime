import ApplicationServices
import CoreGraphics
import Testing
@testable import slime

@Test func closingRequiresOneToOneGeometryAndNeverFallsBackToAnAmbiguousTitle() {
  let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
  let element = AXUIElementCreateApplication(1)
  let entry = AXWindows.Entry(element: element, frame: frame, title: "Document",
    subrole: kAXStandardWindowSubrole, minimized: false)
  #expect(WindowActivator.closeMatch(bounds: frame, entries: [entry], siblingBounds: [frame]) == 0)
  #expect(WindowActivator.closeMatch(bounds: frame, entries: [entry, entry], siblingBounds: [frame]) == nil)
  #expect(WindowActivator.closeMatch(bounds: frame, entries: [entry], siblingBounds: [frame, frame]) == nil)
  #expect(WindowActivator.closeMatch(bounds: frame.offsetBy(dx: 100, dy: 0),
    entries: [entry], siblingBounds: [frame]) == nil)
}
