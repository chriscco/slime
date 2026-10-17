<p align="center">
  <img src="docs/assets/slime-banner.png" alt="Slime — logo and green slime mascot" width="100%">
</p>

<p align="center">
  <a href="README.zh-CN.md">中文说明 →</a>
</p>

A macOS window switcher with two things the system's own switcher doesn't do:
**type-to-search** and **two trigger gestures**.

## Installation

### Download the DMG

Requires **macOS 15 or later**. macOS 15 support is experimental; desktop permission and window-operation validation is pending. This release's package targets **Apple silicon (arm64)**. Intel users can build from source; this release does not provide a validated Intel package.

1. Download the DMG and its `.sha256` file from [GitHub Releases](https://github.com/chriscco/slime/releases).
2. In the download directory, verify it with `shasum -a 256 -c slime-0.0.6-arm64.dmg.sha256`.
3. Open the DMG, drag slime to Applications, eject the image, and launch slime from Applications.

**0.0.6 is locally self-signed and is not notarized by Apple.** If macOS blocks it because the developer cannot be verified, first verify the repository source and checksum, then use **System Settings → Privacy & Security → Open Anyway** for slime and confirm the system prompt. Do not disable Gatekeeper globally. See [Apple's first-launch guidance](https://support.apple.com/en-ie/102445).

DMG users do not need to run signing or build scripts.

### Build from source

Install Xcode Command Line Tools, then run these commands from the repository directory. Full Xcode is not required.

```sh
scripts/setup-signing     # once before building; preserves signing identity across rebuilds
scripts/build-app         # creates build/slime.app
open build/slime.app
```

For a release build, use `CONFIG=release scripts/build-app`.

### First launch

Grant slime **Accessibility** permission in **System Settings → Privacy & Security**. Enable **Screen Recording** for window previews, then quit and reopen slime.

## Gestures

| Keys | What happens |
|---|---|
| Hold `⌘`, tap `Tab` | Cycles windows. **Release `⌘` to switch** — the same feel as the system switcher. |
| Hold `⌥`, tap `Tab` | The same panel, but **it stays up after you release**. Type to search, `Enter` to switch. |
| `⌘F` | Focus the search box. Works in both modes. |
| `Tab` / `⇧Tab` | Move the selection forward / backward. The highlight slides between items. |
| `↑` `↓` `←` `→` | Move the selection. |
| Type anything | Live fuzzy filter. Once you type, releasing `⌘` keeps the panel open. |
| `Enter` | Switch to the selection. Works on minimized windows too. |
| `⌘D` | Close the selected window with a CRT preview animation; the app stays running. |
| `⌘,` | Open settings. Also works after releasing Option. |
| `Esc` | Close without switching. |

The list uses app-level MRU ordering and includes the current window at the end. Optional grouping gives each app its own section. The panel keeps five columns and the same width with fewer than five windows. The underline animates within a row and moves immediately between rows.

slime has no Dock icon and does not appear in the system's own `⌘+Tab` list. It
stays out of the way until you ask for it.

Entries represent **windows rather than apps**, so you can switch directly to a target. Public system APIs cannot reliably discover or operate every offscreen window; see the limitations below.

## Settings

Open Settings from the menu bar or press `⌘,` in the panel.

- **General**: enable slime, group windows by app, launch at login, and choose English (default) or 简体中文. Disabling slime restores native `⌘Tab`.
- **Appearance**: Black, White, Deep Blue, or System background; Liquid Glass or Solid on macOS 26+, with adjustable accent color and corners. Glass controls appear only when that material is selected. The default accent is slime green `#96D76A`.
- **Shortcuts**: view key bindings.
- **About**: version and GitHub repository link.

## Performance

Baseline measured before cross-opening preview reuse, on an Apple M4 / 16 GiB Mac running macOS 27 with two displays, **Stage Manager enabled and windows set aside on the left**. Both modes used the same 11 windows and 12 open/search/dismiss cycles over 20 seconds after warm-up.

| Preview source | Average CPU | Peak memory | Previews available |
|---|---:|---:|---:|
| Cached previews | 9.9% | 29.0 MiB | 3 / 11 |
| Fresh captures (no disk cache) | 10.1% | 34.6 MiB | 8 / 11 |

Choose the mode in **Settings → Appearance → Preview source**. Both modes reuse previews across openings and update changed windows in the background. Fresh captures can show tilted Stage Manager windows without saving previews to disk. Typing does not trigger another capture.

These are process measurements from an isolated release-build harness running the real panel code. CPU 100% means one core; memory is physical footprint. This short, mixed-window sample excludes WindowServer/GPU costs and does not establish a worst-case limit. [Method and full results](docs/validation/2026-10-16-slime-0.0.8-performance.md#stage-manager-follow-up-for-the-readme).

## Requirements

- **macOS 15+**. Liquid Glass requires macOS 26+; macOS 15 uses a solid background and remains experimental.
- Building from source requires a **macOS 26+ SDK** (Xcode 26+ or matching Command Line Tools).
- **Screen Recording permission** enables previews. Without a preview or same-window cache, slime shows an app icon inside a generic mini-window.
- **Accessibility permission.** slime reads the window list through the
  Accessibility API and intercepts the keys you press, so macOS has to grant it.

## Package a release

```sh
scripts/package-dmg
```

The script builds release configuration, names the DMG from the actual architecture, mounts it read-only, verifies version/signature/icon/binary/Applications link, and generates a SHA-256 file. Artifacts are in `build/`. Local self-signing stabilizes development permissions; it is not Developer ID signing or Apple notarization.

Tag-triggered publishing and the English release-note template are documented in the
[publishing guide](docs/releases/README.md).

## Known limitations

Public AX information can cover only part of the available Spaces. Never-observed windows may be missing and ambiguous close targets are refused. Offscreen previews can be stale; a window closed outside slime may take time to disappear if macOS retains its surface. Secure Input uses the system switcher. Unassigned Command-letter combinations remain filter input while the panel is open. Login launch and permission behavior follow system approval prompts.

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
