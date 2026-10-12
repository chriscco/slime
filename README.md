# slime

A macOS window switcher with two things the system's own switcher doesn't do:
**type-to-search** and **two trigger gestures**.

**[中文说明 →](README.zh-CN.md)**

> **Status: 0.0.1.** Usable daily on the main path. 0.0.2 — card grid, Liquid Glass
> panel, settings window — is in progress on
> [PR #29](https://github.com/chriscco/slime/pull/29).

## Gestures

| Keys | What happens |
|---|---|
| Hold `⌘`, tap `Tab` | Cycles windows. **Release `⌘` to switch** — the same feel as the system switcher. |
| Hold `⌥`, tap `Tab` | The same panel, but **it stays up after you release**. Type to search, `Enter` to switch. |
| `⌘F` | Focus the search box. Works in both modes. |
| `Tab` / `⇧Tab` | Move the selection forward / backward. The highlight slides between items. |
| `↑` `↓` `←` `→` | Move the selection. |
| Type anything | Live fuzzy filter — `ghb` matches `Chrome — GitHub`. |
| `Enter` | Switch to the selection. Works on minimized windows too. |
| `Esc` | Close without switching. |

The list is sorted MRU, so the window you used most recently is first.

slime has no Dock icon and does not appear in the system's own `⌘+Tab` list. It
stays out of the way until you ask for it.

It also lists **every window of every app**, not one entry per app — so you can
jump straight to the window you want instead of landing on an app and then
cycling through its windows.

## Requirements

- **macOS 14+** for 0.0.1. 0.0.2 raises the floor to **macOS 26** — it renders the
  panel with `NSGlassEffectView`, which does not exist in earlier releases.
- **Accessibility permission.** slime reads the window list through the
  Accessibility API and intercepts the keys you press, so macOS has to grant it.
- **No third-party dependencies.**

## Build and run

No Xcode needed — the command line tools are enough.

```sh
scripts/setup-signing     # once; keeps the permission grant across rebuilds
scripts/build-app         # builds build/slime.app
open build/slime.app
```

`scripts/build-app` assembles the `.app` bundle by hand — `swift build` plus a
generated `Info.plist` — rather than using an Xcode project. Use
`CONFIG=release scripts/build-app` for a release build.

### Why `setup-signing` is not optional

You run it once, and it is worth the ten minutes.

macOS ties the Accessibility grant to the app's **code signing identity**. An
ad-hoc signature (`codesign -s -`) has nothing but a cdhash as its designated
requirement, so **every rebuild changes the hash and you must re-grant the
permission by hand**. A self-signed certificate anchors the requirement to the
certificate instead, so rebuilds keep the grant. Skip it and you will re-tick
that checkbox dozens of times a day.

## First run

1. slime asks for Accessibility permission and shows the system dialog.
2. Turn slime on under **System Settings → Privacy & Security → Accessibility**.
3. **Quit slime and open it again.** The permission only applies to newly started
   processes. This trips everyone up exactly once.

If slime cannot install its event tap it shows an error and quits rather than
sitting silently in the background. If macOS disables the tap while slime is
running, slime stops intercepting and lets the native `⌘+Tab` take over — the
switcher degrading is always preferable to the keyboard breaking.

## Tests

```sh
scripts/test
```

Uses [swift-testing](https://github.com/swiftlang/swift-testing) (`import Testing`,
not XCTest). The pure logic in `Sources/slime/Core/` is where the tests live — the
trigger state machine especially, because a state machine that swallows the wrong
key breaks the keyboard system-wide, and that risk needs to be exhaustively
unit-testable without a human pressing keys.

## Layout

```
Sources/slime/
  App/      main.swift, AppDelegate.swift, Permission.swift
  Core/     pure logic — Window, Search, Trigger. Foundation only, no AppKit.
  System/   EventTap, WindowEnumerator, WindowCache, WindowActivator
  UI/       PanelWindow, PanelController
Tests/slimeTests/     swift-testing
docs/       specs / plans / modules / templates
scripts/    build-app, test, setup-signing, hooks
```

`Core/` deliberately cannot import AppKit, CoreGraphics, or ApplicationServices.
It is the only layer that can be unit-tested, and letting system APIs in there
turns the project into one you can only verify by clicking around.

## Contributing

Everything goes through **issue → branch → PR → merge**. No direct commits to
`main` — a pre-commit hook enforces it.

- Branches: `feat/` `fix/` `docs/` `chore/`
- Commit subjects: `type(scope): what it did`, e.g.
  `fix(panel): keep the selection when the list refreshes`
- A PR must say **why**, not just what, and must link an issue. Use `Closes #N`
  only when the PR finishes the deliverable, `Refs #N` otherwise.

The full development norms are in [`CLAUDE.md`](CLAUDE.md) (Chinese). Read it
before touching `EventTap` or `WindowEnumerator` — it lists this domain's
correctness red lines, and getting those wrong does not merely look bad, it
breaks the user's machine.

## Docs

| Path | What's in it |
|---|---|
| [`docs/specs/`](docs/specs/) | what each version must do |
| [`docs/modules/`](docs/modules/) | per-module design, decisions, handoffs |

## License

Not chosen yet.
