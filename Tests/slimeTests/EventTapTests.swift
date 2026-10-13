import Foundation

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
