# slime

A macOS window switcher with two things the system's own switcher doesn't do:
**type-to-search** and **two trigger gestures**.

**[中文说明 →](README.zh-CN.md)**

> **Version: 0.0.5.** A five-column panel with rounded previews, optional app groups,
> redesigned settings, and window closing with `⌘D`.

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
| `⌘D` | Close the selected window with a CRT preview animation; the app stays running. |
| `⌘,` | Open settings. Also works after releasing Option. |
| `Esc` | Close without switching. |

The list uses app-level MRU ordering. With grouping enabled, each app starts its own section.

slime has no Dock icon and does not appear in the system's own `⌘+Tab` list. It
stays out of the way until you ask for it.

It also lists **every window of every app**, not one entry per app — so you can
jump straight to the window you want instead of landing on an app and then
cycling through its windows.

## Settings

Open Settings from the menu bar or with `⌘,` while the panel is open.
General contains the enable switch, app grouping, launch at login, and English / 简体中文.
English is the default, including upgrades; existing appearance preferences are preserved.
Appearance keeps the glass style, strength, accent color, and panel corners. Shortcuts
lists the fixed bindings; About shows the bundle version and repository link.

Turning slime off restores native `⌘Tab` without removing the menu bar item.
Login items use macOS status and may require approval in System Settings.

`⌘D` only requests closing the selected window. Ambiguous targets are refused;
a save prompt or failure restores the preview with an explanation. It never quits
an app or responds to a save prompt. Reduce Motion replaces the CRT effect with a fade.

## Requirements

- **macOS 26+** (the panel uses `NSGlassEffectView`).
- **Screen Recording permission** enables previews. Without a preview or same-window cache, slime shows an app icon inside a generic mini-window.
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

If slime cannot install its event tap it shows an error and turns interception off;
the menu bar settings remain available. After granting Accessibility, restart and enable slime in Settings. If macOS disables the tap while slime is
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
  Core/     pure logic — Window, Search, Trigger, GridLayout. Foundation only, no AppKit.
  System/   EventTap, WindowEnumerator, WindowCache, WindowActivator
  UI/       panel, cards, previews, settings
Tests/slimeTests/     swift-testing
docs/       specs / plans / modules / templates
scripts/    build-app, test, setup-signing, hooks
```

`Core/` deliberately cannot import AppKit, CoreGraphics, or ApplicationServices.
Pure state/layout tests need no OS permissions. Additional AppKit tests cover controls
and asynchronous lifecycle; real AX, login items and visual motion still require native checks.

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
