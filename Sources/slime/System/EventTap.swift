import CoreGraphics
import Foundation

/// `CGEvent ↔ Event` 的翻译、吞放、状态机宿主（spec §5 / §6）。
///
/// 线程模型（红线 1）：状态机跑在自己线程的 run loop 上，事件回调里只有
/// 状态机和吞放 —— 没有 AX 调用、不读磁盘、不等锁。要动 UI / 系统的 Effect
/// 全部异步送回主线程。
///
/// lingering 下这一层几乎关闭（spec §6）：键盘走 AppKit 响应链，tap 只盯
/// 「修饰键按下」—— 收到就回 armed 重新接管，其余无脑放行。
/// 最危险的代码，在最不需要工作的时候是关的。
///
/// `@unchecked Sendable` 的理由：状态只在 tap 线程访问；主线程只在 `start()`
/// 里经 semaphore 握手读一次启动结果。没有共享可变状态、没有锁。
final class EventTap: @unchecked Sendable {
  enum StartError: Error {
    case creationFailed
    case timedOut
  }

  /// 连续被系统禁掉几次就进兜底（红线 3）。健康时禁一次、重开就够；
  /// 连续 3 次说明系统持续不给机会 —— 别再赌用户的键盘。
  private static let disableLimit = 3

  /// UI 级 Effect 的执行者，在主线程被调用。
  private let onEffects: @MainActor (State, [Effect]) -> Void
  /// 进兜底模式的通知（红线 3：提示用户）。
  private let onDegraded: @MainActor () -> Void

  private let ready = DispatchSemaphore(value: 0)

  // ── 以下只在 tap 线程访问 ──────────────────────────────────────────
  private var state: State = .idle
  private var tap: CFMachPort?
  private var consecutiveDisables = 0
  private var degraded = false

  // ── 只在构造和 start() 之间（主线程）访问 ──────────────────────────
  private var startError: StartError?

  init(
    onEffects: @escaping @MainActor (State, [Effect]) -> Void,
    onDegraded: @escaping @MainActor () -> Void
  ) {
    self.onEffects = onEffects
    self.onDegraded = onDegraded
  }

  /// 起专用线程装 tap。建不起来抛错 —— spec §9：报错并退出，
  /// 不要静默地在后台运行一个没用的进程。
  func start() throws {
    let thread = Thread { [self] in install() }
    thread.name = "slime.event-tap"
    thread.qualityOfService = .userInteractive
    thread.start()

    guard ready.wait(timeout: .now() + 2) == .success else { throw StartError.timedOut }
    if let error = startError { throw error }
  }

  private func install() {
    // 只关心键盘；鼠标不碰（0.0.1 面板不支持点选）。
    let mask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: Self.callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      startError = .creationFailed
      ready.signal()
      return
    }

    self.tap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    ready.signal()
    CFRunLoopRun()
  }

  private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
  }

  /// 返回 nil 表示吞掉事件，不返回则放行。
  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    // 红线 2：回调超时后系统会直接禁掉 tap，不重开的每一刻 ⌘+Tab 都在
    // 全系统范围内失效。收到必须立刻重开。
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if type == .tapDisabledByTimeout {
        consecutiveDisables += 1
        if consecutiveDisables >= Self.disableLimit {
          degrade()
          return Unmanaged.passUnretained(event)
        }
      }
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }

    // 能正常处理事件 = 系统是健康的，连续计数清零。
    consecutiveDisables = 0

    if degraded { return Unmanaged.passUnretained(event) }

    let translated = Self.translate(type: type, event: event)

    // spec §6：lingering 时键盘走 AppKit 响应链，tap 只盯「修饰键按下」。
    if case .lingering = state {
      if let translated, case .modifierDown = translated {
        transition(translated)
      }
      return Unmanaged.passUnretained(event)
    }

    guard let translated else {
      // 没翻译成 Event 的按键（功能键、keyUp……）：holding 期间吞 ——
      // 会话里键盘归我们（按住 ⌘Tab 时按 ⌘Q、F5 不该透到应用），
      // 其他状态放行。见 docs/modules/system/design.md。
      if case .holding = state { return nil }
      return Unmanaged.passUnretained(event)
    }

    let effects = transition(translated)
    // 放行是默认：只有 Effect 明确要吞才吞（红线 3）。
    return effects.contains(.swallow) ? nil : Unmanaged.passUnretained(event)
  }

  /// 跑纯状态机，把（状态, Effect）发布到主线程执行。返回 Effect 供吞放判断
  /// （lingering 分支不需要 —— 那里一律放行）。
  @discardableResult
  private func transition(_ event: Event) -> [Effect] {
    let (next, effects) = reduce(state, event)
    state = next
    // 必须走 DispatchQueue.main：它严格 FIFO，保证 appendQuery 的顺序 ——
    // 打字乱序不能接受；Task { @MainActor } 不保证跨 Task 的执行顺序。
    DispatchQueue.main.async { [onEffects] in
      MainActor.assumeIsolated { onEffects(next, effects) }
    }
    return effects
  }

  private func degrade() {
    // 红线 3：宁可功能失效，不能让用户没法切 app。停止参与 ——
    // 不重开 tap、之后一律放行、不吞任何事件；通知用户。
    degraded = true
    state = .idle
    DispatchQueue.main.async { [onDegraded] in
      MainActor.assumeIsolated { onDegraded() }
    }
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
        character: character(event)
      )

    default:
      return nil  // keyUp：状态机不感知；进 holding 时按上面的兜底吞
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

/// keyCode → Event 的按键表。两个事件源（EventTap 的 CGEvent、PanelWindow 的
/// NSEvent）共用它 —— spec §6 的两个事件源一个状态机，语义必须一致，
/// 靠两张各写各的表是保不住的。
///
/// shortcut: 快捷键硬编码成 ⌘Tab / ⌥Tab（和这里的 keyCode 一起），被某个
/// app 冲突烦到时再做可配置 —— 那时硬编码要改成一张可读的绑定表。
enum KeyTable {
  /// `character` 传 keyboard-layout 感知、且「忽略修饰键」后的字符。
  static func event(
    keyCode: Int, shift: Bool, commandOrOption: Bool, character: Character?
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
      return .arrow(-1)  // ↑
    case 125:
      return .arrow(1)  // ↓
    case 3 where commandOrOption:
      return .focusSearch  // ⌘F / ⌥F（spec §2 第 6 条：两种模式都要）
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
