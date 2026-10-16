# Window Switching Implementation Plan

> Execute in the isolated `fix/window-switching` worktree; use the subagent-driven-development workflow and review the complete diff afterward.

**Goal:** Implement the owner-approved spec in issue #79 and a new PR stacked on #75.
**Architecture:** Keep immutable Core windows and the existing cache/panel split. Maintain native target identities and focus/title observations in System; use cached identity for bounded activation and actual focus for MRU.
**Tech Stack:** Swift 6, AppKit, public Accessibility/CoreGraphics, swift-testing.

## Global constraints

Use public APIs only. Keep AX IPC off the input/main thread. No hot-path enumeration,
retry loop, screenshot capture, or periodic idle polling. No new dependency. Preserve
#75 behavior. All implementation PR changes belong in 0.0.8 release notes. User merges.

## Task 1 — Identity, title, and activation

Files: WindowEnumerator.swift, WindowActivator.swift, a focused native-target/observer
file if necessary, their tests. Read all callers before editing. Reproduce ambiguous
frame/title selection and stale-title behavior with failing tests. Retain exact AX
references from background enumeration, constrain stale identity lifetime, and prefer
fresh title evidence over remembered text. A direct activation must target only that
identity; app-only fallback must not report exact success. Bound IPC and cancellation.
Run `scripts/test`; verify tests fail before the fix and pass afterward.

## Task 2 — Focus events and window MRU

Files: WindowCache.swift, AppDelegate.swift, native focus observer, cache tests.
Observe the foreground application's focused-window/title changes without polling;
coalesce bursts and remove obsolete observers. Keep background results generation
checked. Test two windows of one app, external focus, stale events, app-only fallback,
and window removal. Produce current-first/window-MRU snapshots while retaining group
sorting as a separate presentation operation. Run `scripts/test` after the change.

## Task 3 — Stable presentation

Files: PanelController.swift and panel tests. Pass current/previous identity from the
cache. Initially highlight the previous window after optional grouping. Freeze session
order while applying fresh Window values and appending new IDs; preserve selection
through title updates/removal/search. Tests must exercise actual controller effects,
not duplicate a sorting implementation. Run `scripts/test` and the signed release build.

## Task 4 — Validation and PR

Record test/build and measured software cost with limits; update system/UI handoff and
release notes. Review the complete diff against the spec and repository rules. Open a
new PR against feat/fresh-previews, link #79, run current-head CI, post an honest review.
Native checks that were not completed remain pending; never substitute synthetic timings
for physical input latency. Do not merge or publish a release.
