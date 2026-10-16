# Background compatibility implementation plan

Goal: implement the approved material spec in PR #78, independent of #76.
Architecture: retain one PanelContentView; use a glass host only when the OS and
saved preference allow it. Settings resolves effective material without mutating defaults.
Stack: Swift 6, AppKit, Swift Testing, GitHub Actions.

## Constraints

macOS 15 minimum, experimental until desktop acceptance. Modern SDK for compilation.
No VM installation, new dependency, or changes to capture/window operations.

## Tasks

- [x] Settings.swift / SettingsTests.swift: first test `panelMaterial` persistence and
  `effectivePanelMaterial(supportsGlass:)` with missing/invalid values and OS changes.
  Store optional `panel.material`; absent defaults resolve to glass only on capable OS.
- [x] PanelWindow.swift / PanelLayoutTests.swift: first assert Solid alpha is 1 at strength
  1 and switching preserves content/search/focus. Replace unconditional glass allocation
  with an availability-guarded host, retaining the same content tree.
- [x] SettingsWindow.swift / SettingsWindowTests.swift: first test material selector,
  conditional glass rows, and a static explanation on unsupported OS. Keep accent/radius.
  Dispatch change callback and rebuild Appearance while restoring keyboard focus.
- [x] Package.swift / scripts/build-app / test.yml: lower deployment and bundle minimum
  to 15; compile on modern SDK and run tests on macOS 15. Exercise real solid fallback
  through tests on that runner; check packaged executable startup separately from TCC.
- [x] README files / app design, decision, handoff / release notes: document both material
  choices and experimental status. Record verified evidence and outstanding desktop checks.
- [x] Run scripts/test, Python script tests, signed bundle build, CI, and review full diff.
  Check #76 integration in a disposable worktree; leave PR open for the user's merge.

For each behavior slice, run scripts/test to observe the missing behavior, implement,
then rerun. Newer-only APIs must be guarded at declaration and use sites.

Visible-window material acceptance remains pending; see the app handoff for the tool limitation.
