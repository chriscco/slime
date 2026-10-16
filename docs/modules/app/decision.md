# App decisions

Historical entries retain their original order. Later entries supersede earlier choices explicitly.

## 2026-10-11 · Swift 6 language mode instead of the spec's Swift 5 lock

- **Context:** This machine has CommandLineTools, not full Xcode, so XCTest is unavailable. The owner requested Swift 6 and its bundled swift-testing to avoid downloading Xcode.
- **Decision:** Use tools version 6.0 and Swift 6 mode for every target, with swift-testing. `scripts/test` supplies local Testing paths; manifest unsafe flags were rejected because SwiftPM transformed them incorrectly for the generated runner.
- **Alternatives rejected:** The original Swift 5 lock in spec §13/CLAUDE.md, and installing several gigabytes of otherwise unnecessary Xcode solely to run tests.
- **Cost:** AppKit must obey strict concurrency using MainActor and documented unchecked boundaries. The original implementation also needed one preconcurrency import for AX keys. CI uses full Xcode; the script probes which toolchain is active.
- **Revisit:** If strict concurrency requires widespread unchecked annotations, or the test environment changes to full Xcode. At the time of this decision, EventTap was the only unchecked boundary.

## 2026-10-11 · Poll authorization, then request a manual restart

- **Context:** Accessibility authorization required restarting the running process in local testing; `AXIsProcessTrusted()` did not change after checking the permission in System Settings.
- **Decision:** Initially, missing permission opened the system prompt, polled once per second for up to two minutes, then explained whether permission succeeded or timed out and exited. Manual instructions included `killall slime`.
- **Alternatives rejected:** Automatic self-relaunch via NSWorkspace adds process-exit, launch, and TCC bundle-path races; retrying in the same process did not apply authorization.
- **Cost:** Authorization and restart were separate user steps. There was initially no Dock or menu-bar restart entry.
- **Revisit:** If restart becomes awkward, add a menu-bar entry or automatic relaunch. The 2026-10-13 entry below supersedes the exit-only behavior.

## 2026-10-11 · Swift and AppKit

- **Context:** The original spec §4 measurements attributed switching latency to AX IPC and WindowServer, with pure CPU work below 0.1 ms.
- **Decision:** Swift/AppKit, pure Swift trigger/search logic, and no dependencies.
- **Alternatives rejected:** Rust cannot remove system API latency and requires roughly two to three times the objc2 glue. Tauri, egui, and winit did not satisfy the nonactivating-panel requirement.
- **Cost:** Accept SwiftPM/CLT limitations, test-path workarounds, and manual app-bundle assembly.
- **Revisit:** Measurements invalidate the original argument, such as pure CPU becoming the bottleneck.

## 2026-10-13 · Preserve settings while disabled; use system login-item truth

Add enabled/group/language preferences, defaulting to enabled, ungrouped, and English. Preserve previous appearance keys. Tap failure or degradation disables interception and shows an error while retaining the menu bar, replacing the old exit-on-error behavior. Ordinary toggling reuses the installed tap.

Settings calls SMAppService directly; there is no forwarding-only service or persisted claim that login launch is enabled. Read status on key-window changes and distinguish approval/errors. Menu, panel, and settings labels share the language preference; real titles remain unchanged.

## 2026-10-13 · One-time green migration and bundled artwork for 0.0.6

The owner confirmed there are no other existing users and requested resetting all old accents to RGB(150, 215, 106). A versioned migration marker makes this a one-time operation; future customization remains intact. Preserve glass settings. Package the supplied artwork as an icns resource and derive About from bundle metadata. Local development signing is not a claim of Developer ID signing or notarization.

## 2026-10-15 · Static theme previews in a scrolling settings body

Show four selectable native button illustrations instead of screenshot assets or live glass surfaces. A split illustration explains System independently of the current appearance. Previews deliberately show opaque base colors; copy explains how glass changes the actual result. Scroll only the body, keeping the sidebar fixed and all existing controls reachable at 720×510 pt. Keep selection controls alive to preserve keyboard focus.

## 0.0.7 owner feedback · Native preview hit regions

The custom drawing covered a large card, but a borderless radio cell did not expose
that rectangle as a trackable mouse area. Direct performClick tests bypassed the bug.
Use a bordered shadowless-square push cell for full native tracking while retaining
custom drawing and explicit radio accessibility. Test actual cell hit regions at
several positions as well as the settings action.

## 2026-10-16 — Reviewed notes and stable signing for tag releases

Release automation publishes the reviewed English version file, not generated commit
logs. Every merged main PR is credited to its GitHub author, validated against commit
association metadata. The existing merge-commit policy defines the first-parent range.
A stable self-signing identity is imported from repository secrets; release mode fails
closed instead of silently changing to ad-hoc. This keeps the current unnotarized
distribution policy. Revisit signing and install guidance together when Developer ID
and notarization become available. See the release spec and publishing guide.

## 2026-10-16 — Keep version-status notices out of READMEs

At the maintainer's request, neither README should announce development versions,
version-specific update summaries, or that the latest DMG is still an older version.
Keep version announcements and release summaries in GitHub Releases and the versioned
release notes; READMEs describe installation and current usage.
