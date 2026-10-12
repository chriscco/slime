// Core/ —— 纯逻辑层，见 Window.swift 顶部注释。

/// 触发状态机（spec §6）。纯函数是刻意的：把「状态机写错 → 吞掉不该吞的按键
/// → 全系统键盘挂掉」这个真实且严重的风险，变成能在单测里穷举的东西 ——
/// 不需要辅助功能权限、不需要 CGEventTap、不需要真人按键。
///
/// 两个事件源（EventTap 的 CGEvent、PanelController 的 NSEvent）翻译成同一个
/// Event 调同一个 reduce；翻译的活在 System/ 和 UI/，不在这一层。

public enum Modifier: Equatable, Sendable {
  case cmd, opt
}

public enum State: Equatable, Sendable {
  case idle
  /// 修饰键按下，还没按 Tab。
  case armed(Modifier)
  /// 面板开着，模式的修饰键还按着。
  ///
  /// `selection` 是无界计数：纯状态机不知道列表长度，加一减一不做钳位。
  /// 真正的显示选中（循环取模、刷新后钳位）由 PanelController 按 Effect 维护。
  case holding(Modifier, query: String, selection: Int)
  /// ⌥ 模式：修饰键已松开，面板留着。
  case lingering(query: String, selection: Int)
}

public enum Event: Equatable, Sendable {
  case modifierDown(Modifier), modifierUp(Modifier)
  case tab(shift: Bool)
  case char(Character), backspace, arrow(Int)  // arrow: -1 上 / +1 下
  case focusSearch                             // ⌘F / ⌥F
  case enter, escape
}

public enum Effect: Equatable, Sendable {
  case passThrough, swallow
  case showPanel(Modifier), hidePanel
  case moveSelection(Int)
  case appendQuery(Character), deleteQueryChar
  case focusSearchField
  case activate, cancel
}

/// 状态转移。`Effect` 里**没有 `swallow` 就默认放行** —— 保底原则：
/// 只有明确要吞的事件才吞，宁可功能失效，不能吞错（红线 3）。
public func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
  switch state {
  case .idle:
    // 在 idle 里一切都别人的：不装手势的时候，键盘完全是应用的。
    if case .modifierDown(let m) = event {
      return (.armed(m), [.passThrough])
    }
    return (state, [.passThrough])

  case .armed(let m):
    switch event {
    case .tab:
      // armed 下 ⇧Tab 与 Tab 等价；方向从进入 holding 之后才有意义。
      return (.holding(m, query: "", selection: 0), [.swallow, .showPanel(m)])
    case .modifierUp(let released):
      // 按下但没按 Tab 就松开 → 用户改主意了。
      return released == m ? (.idle, [.passThrough]) : (state, [.passThrough])
    default:
      // 包括另一个修饰键按下 / 松开：一切放行。⌘C 这类必须还是应用的快捷键。
      return (state, [.passThrough])
    }

  case .holding(let m, let query, let selection):
    if case .modifierUp(let released) = event {
      guard released == m else { return (state, [.passThrough]) }
      switch m {
      case .cmd:
        // 松手切过去。不吞修饰键松开 —— 系统得看到 ⌘ 抬起来了。
        return (.idle, [.activate, .hidePanel])
      case .opt:
        // ⌥ 模式的语义：面板留住。
        return (.lingering(query: query, selection: selection), [.focusSearchField])
      }
    }
    // ⌘ 模式下 ⌘F = 「我要慢慢找」：会话转 lingering —— 松开 ⌘ 不再切换、
    // 回车才切、Esc 取消（用户实测：按 F 想搜索，松 ⌘ 却直接切走了）。
    // ⌥ 模式的松开本来就转 lingering，⌥F 保持 holding 即可。
    if case .focusSearch = event, m == .cmd {
      return (.lingering(query: query, selection: selection), [.swallow, .focusSearchField])
    }

    switch panelStep(event, query: query, selection: selection) {
    case .update(let q, let sel, let effects):
      return (.holding(m, query: q, selection: sel), effects)
    case .finish(let effects):
      return (.idle, effects)
    case nil:
      return (state, [.passThrough])
    }

  case .lingering(let query, let selection):
    if case .modifierDown(let m) = event {
      // lingering 时按 ⌘/⌥ = 开始新手势。关掉 lingering 的面板 —— 不关的话，
      // 接下来的 armed/idle 没有面板窗口的主人，窗口会以「没有状态驱动」
      // 的样子留在屏幕上（spec §6 状态表没写这一格；取舍见 decision.md）。
      return (.armed(m), [.passThrough, .hidePanel])
    }
    if case .modifierUp = event {
      // lingering 是「修饰键已经松开」的状态，再收到松开事件是尾随的，无意义。
      return (state, [.passThrough])
    }
    switch panelStep(event, query: query, selection: selection) {
    case .update(let q, let sel, let effects):
      return (.lingering(query: q, selection: sel), effects)
    case .finish(let effects):
      return (.idle, effects)
    case nil:
      return (state, [.passThrough])
    }
  }
}

/// 面板开着时的键盘转移（spec §6 状态表里 lingering 的「同上转移」）。
/// holding 和 lingering 共用，免得两处实现漂移。
private enum PanelStep {
  /// 会话继续，query / selection 更新。
  case update(query: String, selection: Int, effects: [Effect])
  /// 回车 / Esc：会话结束，回 idle。
  case finish(effects: [Effect])
}

private func panelStep(_ event: Event, query: String, selection: Int) -> PanelStep? {
  switch event {
  case .tab(let shift):
    let direction = shift ? -1 : 1
    return .update(
      query: query, selection: selection + direction,
      effects: [.swallow, .moveSelection(direction)])
  case .char(let c):
    return .update(query: query + String(c), selection: 0, effects: [.swallow, .appendQuery(c)])
  case .backspace:
    return .update(
      query: String(query.dropLast()), selection: 0, effects: [.swallow, .deleteQueryChar])
  case .arrow(let direction):
    return .update(
      query: query, selection: selection + direction,
      effects: [.swallow, .moveSelection(direction)])
  case .focusSearch:
    return .update(query: query, selection: selection, effects: [.swallow, .focusSearchField])
  case .enter:
    return .finish(effects: [.swallow, .activate, .hidePanel])
  case .escape:
    return .finish(effects: [.swallow, .cancel, .hidePanel])
  default:
    return nil
  }
}
