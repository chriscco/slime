# Chinese search implementation plan

> Execute on the existing `feat/0.1.0-chinese-search` branch using subagent-driven-development for implementation and independent review. The approved spec's grilling revision is authoritative.

**Goal:** Deliver native Chinese composition and ordinary single-line editing without breaking global window switching.

**Architecture:** Keep the tap responsible for global trigger gestures and bounded keyboard-session handoff. Native AppKit text editing owns composition and selection; committed full-string changes drive filtering. One reducer owns panel commands, with session invalidation protecting asynchronous delivery.

**Tech stack:** Swift 6, AppKit, CoreGraphics, swift-testing; no new dependencies.

## Constraints

- Keep the nonactivating panel, macOS 15 minimum, and existing runtime dependency set.
- Never block the tap or call UI/AX/I/O in its callback; preserve timeout recovery and native fallback.
- The spec at `docs/specs/2026-10-20-slime-0.1.0-spec.md`, especially Q1–Q10, governs behavior.
- Work stays on this implementation branch; the owner merges the PR.

## Task 1 — Native editing and keyboard ownership

Files: `Sources/slime/Core/Trigger.swift`, `Sources/slime/System/EventTap.swift`,
`Sources/slime/UI/PanelWindow.swift`, `Sources/slime/UI/PanelController.swift`,
`Sources/slime/UI/CardGridView.swift`, `Sources/slime/App/AppDelegate.swift`;
affected tests in `Tests/slimeTests/` and `scripts/fixtures/benchmark.swift`.
Only split a native editor into its own UI file if needed to keep responsibility clear.

- [x] Establish failing behavior tests through existing seams before each implementation slice.
- [x] Cover full-string query updates and repeated-text no-op, Chinese/mixed search, no-result Enter, modifier-release transition, first-key exactly once, and stale events.
- [x] Replace fake text/caret with native editing, preserving surrounding styling. Native marked text does not filter until committed; committed text replaces the whole query.
- [x] Delegate editing keys to the native input system. Intercept panel commands once, only when composition does not own the key. Preserve native selection, clipboard, undo/redo and normalize pasted newlines to spaces.
- [x] Keep held-trigger character compatibility until modifier release; explicit focus enters native editing immediately. Do not leak editor Command combinations to the background app.
- [x] Route actual card clicks to the captured window identity, discard composition on dismissal, reset undo history, and preserve the editor during background refresh.
- [x] Exercise native editing with marked text and replacement ranges in AppKit tests. Keep any system-IME desktop evidence separate.
- [x] Update callers, tests and benchmark fixtures for changed effects; run `scripts/test`, release build, and inspect the final diff.

Behavior checks include:

```swift
#expect(Search.rank(windows, query: "工作").map(\.windowID) == expectedIDs)
// Native editor: setMarkedText("zhou", selectedRange: ..., replacementRange: ...)
// -> existing committed rows remain. insertText("周", replacementRange: ...)
// -> rows use the complete new query. Empty results + Enter -> panel stays visible.
```

Implementation interfaces are scoped to the existing Event/Effect and panel callbacks; do not add a second reducer or generic event-routing framework. The implementation report must document the resulting handoff API and red/green test evidence.

## Task 2 — Review and regression verification

- [x] Independently review Task 1 against all ten confirmed decisions and repository guardrails.
- [x] Correct confirmed defects with regression tests, then re-review changed areas.
- [x] Run the full test command and `CONFIG=release scripts/build-app`; retain evidence.
- [x] Where desktop access permits, exercise the actual nonactivating panel and a system IME. Record exactly what was tested and any remaining manual acceptance; simulated marked text alone is not native-IME acceptance.

## Task 3 — Documentation and PR

Files: `README.md`, `README.zh-CN.md`, settings shortcut copy,
`docs/modules/{trigger,panel}/{design,decision,handoff}.md`,
`docs/releases/0.1.0.md`, `docs/releases/README.md`,
`docs/validation/2026-10-20-chinese-search.md`.

- [x] Document editing/navigation, composition priority, no-results behavior and scoped undo.
- [x] Append architecture decisions; update module contracts and handoff with verified results.
- [x] Create/update English 0.1.0 notes with the actual PR link; preserve frozen notes.
- [x] Open a PR linked to #102. Use `Refs` and draft status if required desktop acceptance remains incomplete; do not claim completion or close the issue prematurely.
- [ ] Follow `.agents/skills/pr-review/SKILL.md`, check current-head CI, report the honest verdict, and leave merging to the owner.

## Progress

- Implementation and independent source review completed; 276 tests and release build pass.
- Actual system Pinyin and Rime editing checked in a production-panel fixture; full global-gesture acceptance remains pending. PR stays draft until that evidence is available.
