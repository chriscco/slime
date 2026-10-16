# App handoff — background compatibility (PR #78)

## Current state

PR #78 includes the spec and implementation independently of #75/#76. It adds
material selection on macOS 26+, opaque fallback on macOS 15, and shared settings.
The package and bundle target 15; compilation still needs a macOS 26+ SDK. Saved
Glass preferences survive unsupported systems, and Solid does not erase glass values.

## Integration

Reconcile shared settings/build files with #76 when it merges. Its appcast generation
reads LSMinimumSystemVersion from the packaged bundle; retain that behavior and the
15.0 bundle floor. Retain Sparkle packaging/signing and its independently valid minimum.
Keep #75 preview source controls alongside the material controls.

## Verification

Local tests exercise material resolution, actual hosts, opacity/theme colors, settings
controls, query/selection preservation, and no window refresh on material changes.
A macOS 15 CI lane runs tests, builds an ad-hoc signed bundle, verifies its Mach-O/plist
minimum, and checks five-second startup with interception disabled. This is not TCC
acceptance. See the PR checks for exact current-head results.

## Remaining native acceptance

macOS 15 remains experimental: startup with real permission grants, optional screenshot
permission, Stage Manager, Spaces/multiple displays, activation and close operations need
an external tester. The development host is macOS 27. The macOS 26+ visible-window material check is
also pending: computer-use inspection timed out and offscreen native controls did not
composite reliably. Do not describe a green CI run as completion of these checks. User performs the merge; no tag/release.


## Implementation evidence

Implementation head `55f8123` passed 183 local Swift tests and 12 script tests, plus
signed release packaging and the five-second launch smoke check. CI run
[38878926193](https://github.com/chriscco/slime/actions/runs/38878926193) passed `test`,
`signing`, and `compatibility` (macOS 15). The first compatibility run found an old
87%-opacity assertion; it now expects opaque Solid on 15. No product workaround was needed.

A disposable integration with #76 passed 190 Swift tests, 18 script tests, signed
release packaging, and launch smoke. Resolve Package.swift by retaining the 15 minimum
and Sparkle dependency; retain both sets of settings initializer parameters/properties;
combine design/decision/handoff documentation. These temporary resolutions were not
merged into either PR branch. No release, tag, or update key changes were made.

## 2026-10-16 — Settings and signed updates (0.0.8)

Current branch: `feat/settings-updates`; implementation issue [#73](https://github.com/chriscco/slime/issues/73).
Earlier sections describe historical work; 0.0.7 is published and 0.0.8 remains unreleased.

Settings now closes locally with Command-W and About contains the bundled rounded banner,
version/repository controls, manual update check, and opt-in automatic checks. App startup
owns a Sparkle adapter; the standard driver handles download and confirmed installation.
Unconfigured local builds expose a clear unavailable state. Sparkle is the justified first
runtime dependency, pinned to 2.10.0; packaging signs its nested helpers with the existing
identity and release CI requires the separate public variable/private update secret.

The isolated signed updater smoke completed download, replacement from build 1 to 2,
and relaunch with a receipt for both zip and DMG updates on arm64 macOS 27.0. Runtime cancellation-before-download, offline, equal/downgrade,
unsupported OS, corrupt/bad-signature archives, and read-only-DMG rejection also preserved
the original isolated app. Script tests reject wrong keys and modified signed data.
See [the durable validation record](../../releases/0.0.8-updates-validation.md) for exact
coverage and gaps. macOS 26 runtime acceptance, standard-dialog interaction, and real slime Accessibility/Screen Recording continuity
after upgrading remain native acceptance work. Light/dark offscreen About renders using
the actual controller and packaged artwork passed visual inspection at 720 pt. No production update key was created/exported, no secret configured, and no release
published. The first updater-enabled version must be installed manually.

Finish PR review/CI and the remaining native gates before the owner merges or publishes.
Follow [the release guide](../../releases/README.md) for one-time update key setup and
release preparation; publishing every future latest release with its appcast is required.

## 2026-10-16 — Full-app update acceptance in progress

The owner approved testing signed full-app builds before merge/release. The isolated
fixture is `/tmp/slime76-acceptance/installed/slime Update Test.app` (8001), with 8002
in a signed DMG. A temporary HTTPS tunnel serves only the signed appcast/DMG; unique
bundle preferences keep the test disabled and automatic checks off. Code signatures
and the HTTPS feed are verified; real dialogs and permissions are not yet accepted.
Native automation times out on the menu-bar-only app. Await the owner's opening of
Settings → About (0.0.8-test1), then continue the standard-dialog checks. Granting
Accessibility/Screen Recording for the test identity needs a user action; no permission
has been granted by setup. Do not mark this PR Ready from fixture preparation alone.
The spec now distinguishes merge checks from unavailable-environment pre-release gates.
Stop the fixture server/tunnel after acceptance; never serve the workspace or keys.

### Accessibility onboarding follow-up

Full-app standard Sparkle offer, download cancellation, explicit installation, and
relaunch passed using the isolated 8001/8002 fixture. See the updates validation
record for the evidence and limits. Permission continuity is still pending.

The owner found that enabling the untrusted app showed an extra slime permission
alert. The final requested behavior is system-prompt-only: call
`AXIsProcessTrustedWithOptions` with prompting enabled, without a slime alert or
forced navigation to System Settings. The user chooses in the macOS dialog; macOS
controls repeat-prompt suppression. Verify this in the rebuilt isolated fixture
before resuming permission continuity. No production permissions changed.

### Permission dialog visibility and enabled startup

Owner acceptance found that the floating Settings window could cover the system
permission dialog. Both Accessibility and Screen Recording requests now hide an
existing Settings window before invoking macOS; reopening Settings still works.
A regression test fails without this behavior, including a delayed key-window
notification. This avoids relying on the system dialog to transfer key status.

Missing Accessibility previously persisted `enabled = false`. It now preserves the
user's preference, so a fresh installation (enabled by default) requests access at
launch and resumes startup after permission is granted and the app restarts.
Explicit user opt-out still persists. The actual enable path is tested with denied
permission across two simulated launches using isolated preferences. All 189 local
tests pass; native visibility and upgrade permission continuity remain pending.
The isolated fixture should now start enabled, replacing its earlier intentionally
disabled setup. Production preferences and permissions remain untouched.

Owner confirmed the system permission dialog is now visible. Follow-up: the Enable
slime switch now reflects actual runtime state, so denying access leaves it off
without discarding startup intent. Its action is separate from appearance/grouping
changes to avoid unrelated permission retries. All 190 local tests pass, including
a denied-enable UI regression. Native confirmation of the switch remains pending.


## Rebased update acceptance completed (2026-10-16)

PR #76 rebased onto main after #78; 194 Swift tests, 18 script tests and signed
release packaging passed. The isolated full-app test1 → test2 update now passes
at `~/Applications/slime Update Test.app`: the owner granted both permissions,
restarted the baseline, then confirmed that the update preserves permissions and
normal panel/previews. Native General showed Enable slime on after replacement.
An initial Launch Services reopen alert coincided with immediate automation access;
the repeat without UI access during replacement had no alert and passed owner
acceptance. Do not read/reactivate a stale app binding during Sparkle replacement.
See `docs/releases/0.0.8-updates-validation.md` for evidence and remaining pre-release
checks; no production permissions or releases were changed.
