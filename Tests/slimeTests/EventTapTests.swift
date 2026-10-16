import Foundation
import CoreGraphics

import Testing
@testable import slime

@Test @MainActor func tapOwnsTheWholeLingeringSession() async {
  var delivered: [Effect] = []
  let tap = EventTap(onEffects: { _, effects in delivered += effects }, onDegraded: {})
  #expect(!tap.process(.modifierDown(.opt)))
  #expect(tap.process(.tab(shift: false)))
  #expect(!tap.process(.modifierUp(.opt)))
  #expect(!tap.process(.modifierDown(.cmd)))
  #expect(tap.process(.openSettings))
  #expect(!tap.process(.modifierUp(.cmd)))
  #expect(!tap.process(.char("x")))
  // FIFO main-queue delivery must finish before assertions.
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume() }
  }
  #expect(delivered.filter { $0 == .openSettings }.count == 1)
  #expect(!delivered.contains(.appendQuery("x")))
}

@Test @MainActor func disablingAndCancellingDiscardQueuedPanelEffects() async {
  var delivered: [Effect] = []
  let tap = EventTap(onEffects: { _, effects in delivered += effects }, onDegraded: {})
  _ = tap.process(.modifierDown(.cmd))
  _ = tap.process(.tab(shift: false))
  tap.configure(enabled: false)
  #expect(!tap.process(.tab(shift: false)))
  #expect(!tap.process(.char("x")))
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume() }
  }
  #expect(!delivered.contains(.showPanel(.cmd)))
  tap.configure(enabled: true)
  _ = tap.process(.modifierDown(.opt))
  #expect(tap.process(.tab(shift: false)))
  _ = tap.process(.modifierUp(.opt))
  tap.cancelSession()
  #expect(!tap.process(.char("x")))
}

@Test @MainActor func closeAutorepeatCannotCloseTheNextWindow() async {
  var effects: [Effect] = []
  let tap = EventTap(onEffects: { _, next in effects += next }, onDegraded: {})
  tap.process(.modifierDown(.cmd)); tap.process(.tab(shift: false))
  tap.process(.closeWindow)
  tap.completeClose()
  #expect(tap.process(.closeWindow, isRepeat: true))
  tap.process(.modifierUp(.cmd))
  await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
  #expect(effects.filter { $0 == .closeWindow }.count == 1)
  #expect(!effects.contains(.activate))
  tap.process(.closeWindow)
  await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
  #expect(effects.filter { $0 == .closeWindow }.count == 2)
}

@Test @MainActor func swallowedKeyDownConsumesExactlyOneMatchingKeyUp() {
  let tap = EventTap(onEffects: { _, _ in }, onDegraded: {})
  tap.noteSwallowedKeyDown(48)
  tap.noteSwallowedKeyDown(48) // Autorepeat is still one physical key press.
  tap.noteSwallowedKeyDown(0)
  #expect(tap.swallowKeyUp(keycode: 48))
  #expect(!tap.swallowKeyUp(keycode: 48))
  #expect(tap.swallowKeyUp(keycode: 0))
}

@Test @MainActor func unmatchedKeyUpPassesWithoutConsumingAnotherKeysPair() {
  let tap = EventTap(onEffects: { _, _ in }, onDegraded: {})
  #expect(!tap.swallowKeyUp(keycode: 12))
  tap.noteSwallowedKeyDown(48)
  #expect(!tap.swallowKeyUp(keycode: 12))
  #expect(tap.swallowKeyUp(keycode: 48))
}

@Test @MainActor func cancellingAndConfiguringClearKeyUpPairs() {
  let tap = EventTap(onEffects: { _, _ in }, onDegraded: {})
  tap.noteSwallowedKeyDown(48)
  tap.noteSwallowedKeyDown(0)
  tap.cancelSession()
  #expect(!tap.swallowKeyUp(keycode: 48))
  #expect(!tap.swallowKeyUp(keycode: 0))
  for enabled in [false, true] {
    tap.noteSwallowedKeyDown(48)
    tap.noteSwallowedKeyDown(0)
    tap.configure(enabled: enabled)
    #expect(!tap.swallowKeyUp(keycode: 48))
    #expect(!tap.swallowKeyUp(keycode: 0))
  }
}

@Test @MainActor func escapeAllowsReopeningWithTheStillHeldModifier() async throws {
  for (modifier, flags) in [(Modifier.cmd, CGEventFlags.maskCommand), (.opt, .maskAlternate)] {
    var delivered: [Effect] = []
    let tap = EventTap(onEffects: { _, effects in delivered += effects }, onDegraded: {})
    func key(_ code: CGKeyCode, flags: CGEventFlags) throws -> Bool {
      let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
      event.flags = flags
      return tap.handle(type: .keyDown, event: event) == nil
    }
    tap.process(.modifierDown(modifier))
    #expect(try key(48, flags: flags))
    #expect(try key(53, flags: flags))
    #expect(try key(48, flags: flags))
    #expect(try key(53, flags: flags))
    #expect(try !key(48, flags: []), "Plain Tab must pass after release")
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    #expect(delivered.filter { $0 == .showPanel(modifier) }.count == 2)
    tap.configure(enabled: false)
    #expect(try !key(48, flags: flags), "Disabled slime must not intercept")
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
  }
}
