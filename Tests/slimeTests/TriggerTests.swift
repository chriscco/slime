import Testing

@testable import slime

/// 一次 reduce 把新状态和 Effect 一起钉住 —— spec §6 的状态表怎么写的就怎么测。
private func expect(
  from state: State,
  on event: Event,
  _ newState: State,
  _ effects: [Effect],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let (stateAfter, effectsAfter) = reduce(state, event)
  #expect(stateAfter == newState, "新状态不对", sourceLocation: sourceLocation)
  #expect(effectsAfter == effects, "Effect 不对", sourceLocation: sourceLocation)
}

// MARK: - idle

@Test func idleModifierDownArms() {
  expect(from: .idle, on: .modifierDown(.cmd), .armed(.cmd), [.passThrough])
  expect(from: .idle, on: .modifierDown(.opt), .armed(.opt), [.passThrough])
}

@Test func idlePassesEverythingElse() {
  // 没在切窗口手势里，一切按键都是别人的。
  expect(from: .idle, on: .tab(shift: false), .idle, [.passThrough])
  expect(from: .idle, on: .char("a"), .idle, [.passThrough])
  expect(from: .idle, on: .enter, .idle, [.passThrough])
  expect(from: .idle, on: .escape, .idle, [.passThrough])
  expect(from: .idle, on: .modifierUp(.cmd), .idle, [.passThrough])
}

// MARK: - armed

@Test func armedTabOpensPanel() {
  expect(
    from: .armed(.cmd), on: .tab(shift: false),
    .holding(.cmd, query: "", selection: 0), [.swallow, .showPanel(.cmd)])
  expect(
    from: .armed(.opt), on: .tab(shift: false),
    .holding(.opt, query: "", selection: 0), [.swallow, .showPanel(.opt)])
  // armed 下 ⇧Tab 与 Tab 等价：都开面板，方向从进入 holding 之后才有意义。
  expect(
    from: .armed(.cmd), on: .tab(shift: true),
    .holding(.cmd, query: "", selection: 0), [.swallow, .showPanel(.cmd)])
}

@Test func armedReleaseWithoutTabGoesIdle() {
  expect(from: .armed(.cmd), on: .modifierUp(.cmd), .idle, [.passThrough])
  expect(from: .armed(.opt), on: .modifierUp(.opt), .idle, [.passThrough])
}

@Test func firstHeldModifierDecidesTheMode() {
  // 先按住 ⌘、再按 ⌥、最后 Tab → 走 ⌘ 模式（spec §6）。
  let afterCmd = reduce(.idle, .modifierDown(.cmd)).0
  let afterOpt = reduce(afterCmd, .modifierDown(.opt)).0
  #expect(afterOpt == .armed(.cmd))

  let (holding, effects) = reduce(afterOpt, .tab(shift: false))
  #expect(holding == .holding(.cmd, query: "", selection: 0))
  #expect(effects == [.swallow, .showPanel(.cmd)])
}

@Test func armedOtherKeysPassThrough() {
  // armed 是最需要保住别人的状态的：⌘C 这类必须是应用自己的快捷键。
  expect(from: .armed(.cmd), on: .char("c"), .armed(.cmd), [.passThrough])
  expect(from: .armed(.cmd), on: .modifierDown(.opt), .armed(.cmd), [.passThrough])
  expect(from: .armed(.cmd), on: .modifierUp(.opt), .armed(.cmd), [.passThrough])
  expect(from: .armed(.cmd), on: .enter, .armed(.cmd), [.passThrough])
  expect(from: .armed(.cmd), on: .backspace, .armed(.cmd), [.passThrough])
  expect(from: .armed(.cmd), on: .arrow(axis: .vertical, step: -1), .armed(.cmd), [.passThrough])
  expect(from: .armed(.cmd), on: .focusSearch, .armed(.cmd), [.passThrough])
}

// MARK: - holding（按住修饰键、面板开着）

@Test func holdingTabCyclesForwardAndBackward() {
  expect(
    from: .holding(.cmd, query: "", selection: 0), on: .tab(shift: false),
    .holding(.cmd, query: "", selection: 1), [.swallow, .moveSelection(axis: .horizontal, step: 1)])
  expect(
    from: .holding(.cmd, query: "", selection: 1), on: .tab(shift: true),
    .holding(.cmd, query: "", selection: 0), [.swallow, .moveSelection(axis: .horizontal, step: -1)])
}

@Test func holdingRepeatedTabsKeepAdvancing() {
  var state = State.holding(.cmd, query: "", selection: 0)
  for expected in 1...5 {
    let (next, effects) = reduce(state, .tab(shift: false))
    #expect(next == .holding(.cmd, query: "", selection: expected))
    #expect(effects == [.swallow, .moveSelection(axis: .horizontal, step: 1)])
    state = next
  }
}

@Test func holdingTypingAppendsAndResetsSelection() {
  expect(
    from: .holding(.cmd, query: "sl", selection: 3), on: .char("a"),
    .holding(.cmd, query: "sla", selection: 0), [.swallow, .appendQuery("a")])
}

@Test func holdingBackspaceRemovesLastChar() {
  expect(
    from: .holding(.cmd, query: "sla", selection: 2), on: .backspace,
    .holding(.cmd, query: "sl", selection: 0), [.swallow, .deleteQueryChar])
}

@Test func holdingBackspaceOnEmptyQueryIsHarmless() {
  expect(
    from: .holding(.cmd, query: "", selection: 0), on: .backspace,
    .holding(.cmd, query: "", selection: 0), [.swallow, .deleteQueryChar])
}

@Test func holdingArrowsMoveSelection() {
  expect(
    from: .holding(.cmd, query: "q", selection: 2), on: .arrow(axis: .vertical, step: -1),
    .holding(.cmd, query: "q", selection: 1), [.swallow, .moveSelection(axis: .vertical, step: -1)])
  expect(
    from: .holding(.cmd, query: "q", selection: 2), on: .arrow(axis: .vertical, step: 1),
    .holding(.cmd, query: "q", selection: 3), [.swallow, .moveSelection(axis: .vertical, step: 1)])
}

@Test func holdingCmdFocusSearchLingersSoModifierCanBeReleased() {
  // ⌘ 模式下 ⌘F =「我要慢慢找」：会话转 lingering —— 松 ⌘ 不切换，回车才切。
  // 用户实测的 bug：之前 ⌘F 后松 ⌘ 会直接切走，想搜索得一直按住 ⌘。
  expect(
    from: .holding(.cmd, query: "sl", selection: 1), on: .focusSearch,
    .lingering(query: "sl", selection: 1), [.swallow, .focusSearchField])
}

@Test func holdingOptFocusSearchKeepsHolding() {
  // ⌥ 模式下 ⌥F 留在 holding：⌥ 松开本来就转 lingering，语义没变。
  expect(
    from: .holding(.opt, query: "sl", selection: 1), on: .focusSearch,
    .holding(.opt, query: "sl", selection: 1), [.swallow, .focusSearchField])
}

@Test func releasingCmdAfterFocusSearchDoesNotSwitch() {
  // 完整路径：⌘Tab → ⌘F → 松 ⌘ → 面板留着；回车才切。
  var (state, _) = reduce(.idle, .modifierDown(.cmd))
  (state, _) = reduce(state, .tab(shift: false))
  (state, _) = reduce(state, .char("s"))
  (state, _) = reduce(state, .focusSearch)
  #expect(state == .lingering(query: "s", selection: 0))

  let (afterRelease, releaseEffects) = reduce(state, .modifierUp(.cmd))
  #expect(afterRelease == .lingering(query: "s", selection: 0))
  #expect(releaseEffects == [.passThrough])  // 不激活、不隐藏

  let (afterEnter, enterEffects) = reduce(afterRelease, .enter)
  #expect(afterEnter == .idle)
  #expect(enterEffects == [.swallow, .activate, .hidePanel])
}

@Test func holdingEnterActivates() {
  expect(
    from: .holding(.cmd, query: "sla", selection: 0), on: .enter,
    .idle, [.swallow, .activate, .hidePanel])
}

@Test func holdingEscapeCancels() {
  expect(
    from: .holding(.cmd, query: "sla", selection: 0), on: .escape,
    .idle, [.swallow, .cancel, .hidePanel])
}

@Test func holdingCmdReleaseActivates() {
  // 松手切过去。不吞修饰键松开 —— 系统得看到 ⌘ 已经抬起来了。
  expect(
    from: .holding(.cmd, query: "sla", selection: 1), on: .modifierUp(.cmd),
    .idle, [.activate, .hidePanel])
}

@Test func holdingOptReleaseLingers() {
  // ⌥ 模式的语义：松手后面板留住，焦点进搜索框（spec §6 两个手势两种语义）。
  expect(
    from: .holding(.opt, query: "sla", selection: 1), on: .modifierUp(.opt),
    .lingering(query: "sla", selection: 1), [.focusSearchField])
}

@Test func holdingOtherModifierEventsAreIgnored() {
  expect(
    from: .holding(.cmd, query: "q", selection: 0), on: .modifierUp(.opt),
    .holding(.cmd, query: "q", selection: 0), [.passThrough])
  expect(
    from: .holding(.cmd, query: "q", selection: 0), on: .modifierDown(.opt),
    .holding(.cmd, query: "q", selection: 0), [.passThrough])
}

// MARK: - lingering（⌥ 模式：修饰键已松开、面板留着）

@Test func lingeringTypingContinuesSession() {
  expect(
    from: .lingering(query: "sl", selection: 2), on: .char("a"),
    .lingering(query: "sla", selection: 0), [.swallow, .appendQuery("a")])
}

@Test func lingeringTabMovesSelection() {
  expect(
    from: .lingering(query: "", selection: 0), on: .tab(shift: false),
    .lingering(query: "", selection: 1), [.swallow, .moveSelection(axis: .horizontal, step: 1)])
}

@Test func tabMovesHorizontally() {
  expect(
    from: .holding(.cmd, query: "", selection: 0), on: .tab(shift: false),
    .holding(.cmd, query: "", selection: 1),
    [.swallow, .moveSelection(axis: .horizontal, step: 1)])
}

@Test func lingeringEnterActivates() {
  expect(
    from: .lingering(query: "sla", selection: 2), on: .enter,
    .idle, [.swallow, .activate, .hidePanel])
}

@Test func lingeringEscapeCancels() {
  expect(
    from: .lingering(query: "sla", selection: 2), on: .escape,
    .idle, [.swallow, .cancel, .hidePanel])
}

@Test func lingeringModifierDownStartsNewGesture() {
  // lingering 时按 ⌘/⌥ = 新手势。要关面板：不关的话状态是 armed/idle，
  // 却没有主人驱动那个还挂着的窗口 —— 规格状态表没写这格，取舍记在 decision.md。
  expect(
    from: .lingering(query: "sla", selection: 2), on: .modifierDown(.cmd),
    .armed(.cmd), [.passThrough, .hidePanel])
  expect(
    from: .lingering(query: "sla", selection: 2), on: .modifierDown(.opt),
    .armed(.opt), [.passThrough, .hidePanel])
}

@Test func lingeringModifierUpIsIgnored() {
  expect(
    from: .lingering(query: "", selection: 0), on: .modifierUp(.opt),
    .lingering(query: "", selection: 0), [.passThrough])
}

// MARK: - 完整生命周期

@Test func cmdModeLifecycleEndsWithActivate() {
  var (state, _) = reduce(.idle, .modifierDown(.cmd))
  #expect(state == .armed(.cmd))

  (state, _) = reduce(state, .tab(shift: false))
  #expect(state == .holding(.cmd, query: "", selection: 0))

  // 按住 ⌘ 打字：s、l、a 进 query（手动验收清单里的「打字 sla」）。
  for c in "sla" { (state, _) = reduce(state, .char(c)) }
  #expect(state == .holding(.cmd, query: "sla", selection: 0))

  let (final, effects) = reduce(state, .modifierUp(.cmd))
  #expect(final == .idle)
  #expect(effects == [.activate, .hidePanel])
}

@Test func optModeLifecycleLeavesPanelUp() {
  var (state, _) = reduce(.idle, .modifierDown(.opt))
  (state, _) = reduce(state, .tab(shift: false))

  // 松开 ⌥：面板留住、焦点进搜索框。
  let (lingering, effects) = reduce(state, .modifierUp(.opt))
  #expect(lingering == .lingering(query: "", selection: 0))
  #expect(effects == [.focusSearchField])

  // 归留里打字、回车 → 切过去。
  (state, _) = reduce(lingering, .char("s"))
  let (final, enterEffects) = reduce(state, .enter)
  #expect(final == .idle)
  #expect(enterEffects == [.swallow, .activate, .hidePanel])
}

@Test func lingeringThenNewTabStartsFreshSession() {
  // ⌥Tab 起 → 松 ⌥归留 → 按 ⌘（新手势）→ Tab → 新会话 query 归零。
  var (state, _) = reduce(.idle, .modifierDown(.opt))
  (state, _) = reduce(state, .tab(shift: false))
  (state, _) = reduce(state, .char("x"))
  (state, _) = reduce(state, .modifierUp(.opt))
  (state, _) = reduce(state, .modifierDown(.cmd))

  let (fresh, effects) = reduce(state, .tab(shift: false))
  #expect(fresh == .holding(.cmd, query: "", selection: 0))
  #expect(effects == [.swallow, .showPanel(.cmd)])
}

// MARK: - ⌘,（spec §9）

@Test func commaWhileThePanelIsUpOpensSettings() {
  // 面板开着：吃掉逗号、开设置、会话结束回 idle（面板由 Effect 的执行者藏起来）。
  expect(
    from: .holding(.cmd, query: "sl", selection: 1), on: .openSettings,
    .idle, [.swallow, .openSettings])
  expect(
    from: .lingering(query: "sl", selection: 1), on: .openSettings,
    .idle, [.swallow, .openSettings])
}

@Test func commaWithoutThePanelPassesThrough() {
  // 面板还没开（armed）：⌘, 是别人的快捷键，原样放行。
  expect(from: .armed(.cmd), on: .openSettings, .armed(.cmd), [.passThrough])
  expect(from: .idle, on: .openSettings, .idle, [.passThrough])
}
