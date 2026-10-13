import CoreGraphics
import Foundation

/// State lives on the tap run loop. Main-actor controls enqueue changes there;
/// revision-gated deliveries discard effects queued before dismissal/disable.
/// @unchecked Sendable: the run-loop reference is published once by start's
/// semaphore; mutable keyboard state is only accessed on that run loop.
final class EventTap: @unchecked Sendable {
  enum StartError: Error { case creationFailed, timedOut }
  private let onEffects: @MainActor (State, [Effect]) -> Void
  private let onDegraded: @MainActor () -> Void
  private let ready = DispatchSemaphore(value: 0)
  private var runLoop: CFRunLoop?
  private var startError: StartError?
  @MainActor private var deliveryRevision = 0

  private var revision = 0
  private var state: State = .idle
  private var enabled = true
  private var degraded = false
  private var tap: CFMachPort?
  private var consecutiveDisables = 0
  private var swallowedKeys: Set<Int64> = []

  init(onEffects: @escaping @MainActor (State, [Effect]) -> Void,
       onDegraded: @escaping @MainActor () -> Void) {
    self.onEffects = onEffects
    self.onDegraded = onDegraded
  }

  func start() throws {
    let accepted = DispatchSemaphore(value: 0)
    let thread = Thread { [self] in install(accepted: accepted) }
    thread.name = "slime.event-tap"
    thread.qualityOfService = .userInteractive
    thread.start()
    guard ready.wait(timeout: .now() + 2) == .success else { throw StartError.timedOut }
    if let error = startError { throw error }
    accepted.signal()
  }

  @MainActor func configure(enabled: Bool) {
    reset(enabled: enabled)
  }

  @MainActor func cancelSession() { reset(enabled: nil) }

  @MainActor func completeClose() {
    let expectedRevision = deliveryRevision
    let finish: @Sendable () -> Void = { [self] in
      guard revision == expectedRevision else { return }
      process(.closeFinished, isKeyDown: false)
    }
    if let runLoop {
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, finish)
      CFRunLoopWakeUp(runLoop)
    } else { finish() }
  }

  @MainActor private func reset(enabled: Bool?) {
    deliveryRevision += 1
    let nextRevision = deliveryRevision
    let change: @Sendable () -> Void = { [self] in
      revision = nextRevision
      state = .idle
      if let enabled {
        self.enabled = enabled
        if enabled {
          degraded = false
          consecutiveDisables = 0
          if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
      }
      swallowedKeys.removeAll()
    }
    if let runLoop {
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, change)
      CFRunLoopWakeUp(runLoop)
    } else {
      // Before installation (and in tests) there is no worker owning this state.
      change()
    }
  }

  private func install(accepted: DispatchSemaphore) {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
      eventsOfInterest: mask, callback: Self.callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      startError = .creationFailed
      ready.signal()
      return
    }
    self.tap = tap
    runLoop = CFRunLoopGetCurrent()
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: false)
    ready.signal()
    // No callbacks run until start() accepts the installation. A late startup
    // must not leave an orphan tap swallowing keys after the caller reports failure.
    guard accepted.wait(timeout: .now() + 2) == .success else {
      CFMachPortInvalidate(tap)
      return
    }
    CGEvent.tapEnable(tap: tap, enable: true)
    CFRunLoopRun()
  }

  private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
      .handle(type: type, event: event)
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if type == .tapDisabledByTimeout {
        consecutiveDisables += 1
        if consecutiveDisables >= 3 {
          degraded = true
          state = .idle
          DispatchQueue.main.async { [onDegraded] in onDegraded() }
          return Unmanaged.passUnretained(event)
        }
      }
      if let tap, !degraded { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    consecutiveDisables = 0
    guard enabled, !degraded else { return Unmanaged.passUnretained(event) }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if type == .keyUp {
      return swallowKeyUp(keycode: code) ? nil : Unmanaged.passUnretained(event)
    }
    let swallow = process(Self.translate(type: type, event: event),
      isKeyDown: type == .keyDown,
      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    if swallow, type == .keyDown { noteSwallowedKeyDown(code) }
    return swallow ? nil : Unmanaged.passUnretained(event)
  }

  // Called only on the tap run loop, or before installation in tests.
  func noteSwallowedKeyDown(_ keycode: Int64) { swallowedKeys.insert(keycode) }

  func swallowKeyUp(keycode: Int64) -> Bool { swallowedKeys.remove(keycode) != nil }

  /// The same event path is exercised without installing a global tap in tests.
  @discardableResult
  func process(_ event: Event?, isKeyDown: Bool = true, isRepeat: Bool = false) -> Bool {
    guard enabled, !degraded else { return false }
    guard let event else { return isKeyDown && state.isSessionOpen }
    if event == .closeWindow, isRepeat { return state.isSessionOpen }
    let (next, effects) = reduce(state, event)
    state = next
    let delivery = revision
    DispatchQueue.main.async { [self] in
      guard delivery == deliveryRevision else { return }
      onEffects(next, effects)
    }
    return effects.contains(.swallow)
  }

  // MARK: - 翻译（CGEvent → Event）

  /// 翻译的活属于 System/，不在 Core/Trigger（CLAUDE.md 第六条）。
  private static func translate(type: CGEventType, event: CGEvent) -> Event? {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    switch type {
    case .flagsChanged:
      // flagsChanged 报的是「变化后」的状态：键码指出哪个修饰键动了，
      // flags 指出它现在是按下还是松开 —— 不需要记上一次的 flags。
      switch keyCode {
      case 55, 54:  // 左 / 右 ⌘
        return flags.contains(.maskCommand) ? .modifierDown(.cmd) : .modifierUp(.cmd)
      case 58, 61:  // 左 / 右 ⌥
        return flags.contains(.maskAlternate) ? .modifierDown(.opt) : .modifierUp(.opt)
      default:
        return nil  // ⇧ / Caps：不进状态机；Tab 的 shift 现读
      }

    case .keyDown:
      return KeyTable.event(
        keyCode: Int(keyCode),
        shift: flags.contains(.maskShift),
        commandOrOption: flags.contains(.maskCommand) || flags.contains(.maskAlternate),
        character: character(event),
        command: flags.contains(.maskCommand)
      )

    default:
      return nil  // keyUp 在 handle 中按已吞 keyDown 配对，不进入状态机
    }
  }

  /// 打字进 query 的字符。读前摘掉 ⌥ 标志、读后还原：⌘ 模式打字要走这里，
  /// 得是 "s" 不是 ⌥s 的 "ß"（⇧ 保留，大写是正常的输入）。
  private static func character(_ event: CGEvent) -> Character? {
    let savedFlags = event.flags
    event.flags = savedFlags.subtracting(.maskAlternate)
    defer { event.flags = savedFlags }

    var length = 0
    event.keyboardGetUnicodeString(
      maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
    guard length > 0, length <= 8 else { return nil }  // 死键等没有字符

    var buffer = [UniChar](repeating: 0, count: length)
    event.keyboardGetUnicodeString(
      maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
    return String(decoding: buffer.prefix(length), as: UTF16.self).first
  }
}

/// keyCode → Event 的按键表，由 EventTap 统一翻译全部面板会话。
///
/// shortcut: 快捷键硬编码成 ⌘Tab / ⌥Tab（和这里的 keyCode 一起），被某个
/// app 冲突烦到时再做可配置 —— 那时硬编码要改成一张可读的绑定表。
enum KeyTable {
  /// `character` 传 keyboard-layout 感知、且「忽略修饰键」后的字符。
  static func event(
    keyCode: Int, shift: Bool, commandOrOption: Bool, character: Character?, command: Bool = false
  ) -> Event? {
    switch keyCode {
    case 48:
      return .tab(shift: shift)
    case 36, 76:  // 主 / 小键盘回车
      return .enter
    case 51:
      return .backspace
    case 53:
      return .escape
    case 126:
      return .arrow(axis: .vertical, step: -1)  // ↑
    case 125:
      return .arrow(axis: .vertical, step: 1)  // ↓
    case 123:
      return .arrow(axis: .horizontal, step: -1)  // ←
    case 124:
      return .arrow(axis: .horizontal, step: 1)  // →
    case 2 where command:
      return .closeWindow
    case 3 where commandOrOption:
      return .focusSearch  // ⌘F / ⌥F（spec §2 第 6 条：两种模式都要）
    case 43 where commandOrOption:
      return .openSettings  // ⌘, / ⌥,（spec §9）。裸 `,` 掉进 default → .char(",")
    default:
      guard let character, !character.isControlLike else { return nil }
      return .char(character)
    }
  }
}

extension Character {
  /// 控制字符不翻译成 Event（回车 / Esc / Tab 已被 keycode 分支接走，这是兜漏网）。
  var isControlLike: Bool {
    unicodeScalars.allSatisfy { $0.value < 0x20 || $0.value == 0x7F }
  }
}
