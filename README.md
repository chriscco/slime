# slime

A macOS window switcher with two things the system's own switcher doesn't do:
**type-to-search** and **two trigger gestures**.

**[中文说明 →](README.zh-CN.md)**

> **Version: 0.0.6.** Slime-green accents, a new icon, visible search focus, and refined window closing and animation.

## Install the DMG

Requires **macOS 26 or later**. This release's package targets **Apple silicon (arm64)**. Intel users can build from source; this release does not provide a validated Intel package.

1. Download the DMG and its `.sha256` file from [GitHub Releases](https://github.com/chriscco/slime/releases).
2. In the download directory, verify it with `shasum -a 256 -c slime-0.0.6-arm64.dmg.sha256`.
3. Open the DMG, drag slime to Applications, eject the image, and launch slime from Applications.

**0.0.6 is locally self-signed and is not notarized by Apple.** If macOS blocks it because the developer cannot be verified, first verify the repository source and checksum, then use **System Settings → Privacy & Security → Open Anyway** for slime and confirm the system prompt. Do not disable Gatekeeper globally. See [Apple's first-launch guidance](https://support.apple.com/en-ie/102445).

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

The list uses app-level MRU ordering and includes the current window at the end. Optional grouping gives each app its own section. The panel keeps five columns and the same width with fewer than five windows. The underline animates within a row and moves immediately between rows.

slime has no Dock icon and does not appear in the system's own `⌘+Tab` list. It
stays out of the way until you ask for it.

Entries represent **windows rather than apps**, so you can switch directly to a target. Public system APIs cannot reliably discover or operate every offscreen window; see the limitations below.

## Settings

Open Settings from the menu bar or with `⌘,` while the panel is open.
General contains the enable switch, app grouping, launch at login, and English / 简体中文.
English is the default. On first launch, 0.0.6 resets old accents once to slime green `#96D76A` (RGB 150, 215, 106); subsequent custom colors persist. Glass preferences are preserved.
Appearance keeps the glass style, strength, accent color, and panel corners. Shortcuts
lists the fixed bindings; About shows the bundle version and repository link.

Turning slime off restores native `⌘Tab` without removing the menu bar item.
Login items use macOS status and may require approval in System Settings.

`⌘D` requests closing the selected window without quitting the app or answering save dialogs. Selection tint, title, and underline fade at the start; only the preview plays CRT. A direct failure restores them. Confirmed removal animates panel height when rows disappear. Reduce Motion uses a fade and immediate geometry changes.

When direct access is unavailable, slime attempts to reveal the target app and revalidate the window. The panel dismisses and does not return automatically after closing or confirmation. Ambiguous targets are never guessed. Automatic identification, retries, and confirmation share a three-second budget; system AX calls may return later than the requested timeout.

Typing after `⌘Tab` keeps the panel open when you release Command; `⌘F` is optional. Without typing, releasing Command still switches immediately. Search focus has a 2pt accent border and an end caret that updates immediately without sliding. Typing appends to the query, Backspace deletes its final character, and arrows still select windows. This version does not implement text selection, arbitrary caret placement, or IME composition.

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

## Package a release

```sh
scripts/package-dmg
```

The script builds release configuration, names the DMG from the actual architecture, mounts it read-only, verifies version/signature/icon/binary/Applications link, and generates a SHA-256 file. Artifacts are in `build/`. Local self-signing stabilizes development permissions; it is not Developer ID signing or Apple notarization.

## Known limitations

Public AX information can cover only part of the available Spaces. Never-observed windows may be missing and ambiguous close targets are refused. Offscreen previews can be stale; a window closed outside slime may take time to disappear if macOS retains its surface. Secure Input uses the system switcher. Unassigned Command-letter combinations remain filter input while the panel is open. Login launch and permission behavior follow system approval prompts.

## Tests

```sh
scripts/test
```

Uses [swift-testing](https://github.com/swiftlang/swift-testing) (`import Testing`,
not XCTest). `Tests/slimeTests/` covers Core logic, AppKit controls, and asynchronous
lifecycles. Trigger tests exhaustively check keyboard interception; native acceptance
still verifies actual system behavior.

`scripts/benchmark` measures release-build query/layout/offscreen painting for
10/50/100 windows. It is a CPU benchmark, not input-to-display latency; see the
[validation record](docs/releases/0.0.6-validation.md).

## Layout

```text
slime/
├── Package.swift
├── Resources/
│   ├── slime.png
│   └── slime.icns
├── Sources/slime/
│   ├── App/
│   ├── Core/
│   ├── System/
│   └── UI/
├── Tests/slimeTests/
├── docs/
│   ├── specs/
│   ├── plans/
│   ├── modules/
│   ├── releases/
│   └── templates/
├── scripts/
│   ├── build-app
│   ├── package-dmg
│   ├── benchmark
│   ├── fixtures/
│   ├── test
│   ├── setup-signing
│   └── hooks/
└── .github/workflows/
    └── test.yml
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

The full development norms are in [`CLAUDE.md`](CLAUDE.md) (English). Read it
before touching `EventTap` or `WindowEnumerator` — it lists this domain's
correctness red lines, and getting those wrong does not merely look bad, it
breaks the user's machine.

## Docs

| Path | What's in it |
|---|---|
| [`docs/specs/`](docs/specs/) | what each version must do |
| [`docs/modules/`](docs/modules/) | per-module design, decisions, handoffs |

## License

Licensed under the [MIT License](LICENSE).
