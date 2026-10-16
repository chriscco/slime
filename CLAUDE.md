# CLAUDE.md — slime Development Guidelines

## What this project is

A macOS window switcher with two core features: **type-to-search** and **dual trigger gestures**
(⌘+Tab switches on release / ⌥+Tab keeps the panel open on release).

**The goal is to quickly iterate toward a core workflow usable every day**, rather than
build a complete product. See `docs/specs/2026-10-11-slime-0.0.1-spec.md` for the 0.0.1 scope.

---

## Rule 1: KISS / YAGNI

Before writing code, climb this ladder and **stop at the first viable step**:

1. Does this need to exist? Skip speculative requirements and say so in the reply.
2. Does it already exist in the repository? Search before writing. Duplicating an implementation a few files away is a common source of waste.
3. Can the standard library or language built-ins do it?
4. **Does the platform already provide it?** Use AppKit and system APIs where they cover the need.
5. Can an installed dependency solve it? **Sparkle is the sole third-party runtime dependency**, scoped to updates; additional dependencies require a separate justification.
6. Can it be one line?
7. Only when none of the above works, write the smallest viable implementation.

**Specific restrictions**

- Do not create an interface for one implementation, a factory for one product, or configuration for a value that never changes.
- Do not leave scaffolding “for later”; build it when needed.
- Prefer deleting code to adding it. Boring beats clever: someone has to decipher clever code at 3 a.m.
- **TDD**: for behavior changes, first write a failing test that observes behavior through a public interface, then write the smallest implementation that passes it.
  Work on one red → green vertical slice at a time.
- Put tests in `Tests/slimeTests/`, using **swift-testing** (`import Testing`, not XCTest).
  Run `scripts/test` before committing locally; the script contains the workaround for this machine's Testing paths.
- Mark deliberate shortcuts with a `shortcut:` comment stating the limit and upgrade path.

**Where KISS matters most in this project**: the pure logic files in `Core/`
(`Window`, `Search`, `Trigger`, `GridLayout`) are the only parts that can be unit-tested.
Pulling system APIs into `Core/` would leave the project verifiable only through manual
interaction, effectively giving up automated testing.

---

## Rule 2: Development workflow — no direct changes to main

Every change follows **issue → branch → PR → merge**:

```sh
gh issue create --title "..." --body "..."       # 1. Record the requirement in an issue
git switch -c feat/<short-description>          # 2. Branch from the latest main
git commit -m "..."                            # 3. Commit in small steps
git push -u origin feat/<short-description>     # 4. Push the branch
gh pr create --fill --body "Closes #<issue>"     # 5. Open a PR and link the issue
gh pr merge --merge --delete-branch \
  -t "Merge pull request #<N> from chriscco/<branch>" \
  -b "<PR title>"                              # 6. Merge and delete the branch (user only)
```

**Use a merge commit, not squash.** Each small commit preserves a traceable change,
including its reasoning and pitfalls. Squashing discards that history, even though
preserving why a line looks the way it does is the point of the issue/PR workflow.
Use this consistent merge-commit format:

```
Merge pull request #N from chriscco/<branch>
                                        ← blank line
<PR title>
```

Without `-t`, gh defaults to the PR title, which does not match this format.
Use `-t` for the subject and `-b` for the PR title in the body.

After opening a PR, **you must review it yourself using `.agents/skills/pr-review/SKILL.md`**,
post the verdict as a PR comment, and fix it until Ready. **The user always performs
the merge personally**: leave the Ready PR open for the user to review and merge.
Do not merge it yourself.

The local `pre-commit` hook **rejects commits on main**. Enable it once after cloning:

```sh
git config core.hooksPath scripts/hooks
```

**Exception**: repository bootstrap commits may go directly onto main: the first spec,
guidelines, templates, hooks, and build scripts. **Bootstrap ends when
`.github/workflows/test.yml` first passes on main.** There are no exceptions after that.

Branch prefixes: `feat/` `fix/` `docs/` `chore/`

PRs must explain **why**, not just what changed.
Behavior changes must include tests in the same commit. Documentation-only or static-configuration
changes may omit new tests, but must still run the full test command.

### Commit-message format

**Every non-merge commit subject must follow `type(scope): what changed`.** Examples:

```
feat(trigger): add the pure state machine
fix(panel): keep the selection when the list refreshes
docs(norms): record the commit-message format
chore(scripts): probe the toolchain in scripts/test
```

- Types match the branch prefixes: `feat` / `fix` / `docs` / `chore`.
- Scope is the affected module (`trigger`, `search`, `window`, `system`, `panel`, `app`, `scripts`, `norms`, etc.), not a file path.
- Put one space after the colon, followed by a lowercase imperative describing the change. Put **why** and other details in the body.
- Merge commits are exempt: keep GitHub's `Merge pull request #N from chriscco/<branch>` format.

### Commit author

**The author must be `chriscco <2444628489c@gmail.com>`.** This is already set in the
local Git configuration (`--local`, without affecting other repositories).
Do not inherit another identity from the environment.

### Issues and PR reviews

- Use the English template `.github/ISSUE_TEMPLATE/issue.md` by default, or
  `.github/ISSUE_TEMPLATE/issue-zh.md` for Chinese issues. State the goal, reason,
  scope, and falsifiable acceptance criteria.
- When reviewing a PR or posting a review comment, read and follow `.agents/skills/pr-review/SKILL.md`.

### Every PR must link an issue — use the right relationship

| Syntax | When to use it | Effect on merge |
|---|---|---|
| `Closes #N` | The PR **completes** the issue's deliverables | Automatically closes the issue |
| `Refs #N` | The PR completes only part of the work, such as a spec without implementation | Links the issue; **does not close it** |

**Every merged PR must close its linked issue (`Closes #N`); do not merge `Refs #N` PRs.**

**Misusing `Closes` closes unfinished issues.** An issue closed before the work is done
is worse than an open one: it disappears from the task list and gets forgotten.

**PRs without linked issues are not allowed.** Create an issue first if none exists;
it costs much less than reconstructing why a line was written later.

---

## Rule 3: When to write each document

**Every PR must update the current unreleased version’s release notes in the same PR**,
including features, bug fixes, documentation, maintenance, and release preparation.
**Exception: spec-focused PRs omit release-note entries** and use the reviewed
`release-notes:skip` label described in the workflow below.
Follow [the release-note workflow](docs/releases/README.md#maintain-notes-in-every-pr)
for the current version, entry format, and frozen-version rollover. Reviewers must
verify the entry matches the PR’s final scope, or confirm the spec exemption, before
marking it Ready.

Other documentation must also pass KISS/YAGNI. Use these thresholds:

| Document | Required when | Location |
|---|---|---|
| spec | A **substantial requirement** spans multiple modules, spans multiple sessions, or involves a meaningful tradeoff; any one is sufficient | `docs/specs/YYYY-MM-DD-<kebab-description>-spec.md` |
| plan | A spec needs **tasks with ordering dependencies** and cannot be completed in one session; the plan describes how, the spec describes what | `docs/plans/YYYY-MM-DD-<kebab-description>.md` |
| design | A module exceeds 150 lines **or** has correctness assumptions | `docs/modules/<module>/design.md` |
| decision | **Append an entry for every tradeoff worth revisiting**; append only, never rewrite history | `docs/modules/<module>/decision.md` |
| handoff | Update at session end or handoff with current status, next steps, and pitfalls | `docs/modules/<module>/handoff.md` |

Small changes need no spec; open a PR directly. Templates are in `docs/templates/`.

**Spec delivery:** include a spec in its implementation PR when it describes one
implementation scope. Open a separate spec PR only when the spec coordinates multiple
features that will be implemented in separate PRs. Review and implement a single-scope
spec on the same branch; a separate spec merge is not a prerequisite.

**Existing project tradeoffs worth recording in `decision.md`** when documenting the
relevant module: Swift over Rust; a pure-function trigger state machine; no thumbnails
in 0.0.1; cached snapshots instead of incremental AXObserver updates; public
ScreenCaptureKit instead of private SkyLight for thumbnails; window identity instead
of generation counters for stale results. See spec §4 / §6 / §7 for the reasoning.

---

## Rule 4: Correctness guardrails for this domain

Getting these wrong in a window switcher **is not a style issue**: it can break the
user's machine.

1. **Never block the event-tap callback.** No AX calls, disk access, or waiting for locks;
   only state-machine processing and event swallowing.

2. **Handle `kCGEventTapDisabledByTimeout`.** If the callback times out, macOS disables
   the tap. **At that point, ⌘+Tab stops working system-wide until the user restarts
   slime.** Immediately call `CGEventTapEnable(tap, true)` when notified.

3. **Provide a fallback.** If the system repeatedly disables the tap, stop swallowing
   events, fall back to native ⌘+Tab, and notify the user.
   **A failed feature is preferable to preventing the user from switching apps.**

4. **Enumerate windows on a background thread.** AX uses synchronous cross-process IPC;
   running it on the main thread causes a beachball when the shortcut is pressed.

5. **Discard stale results.** Keep a generation counter on the main thread and discard
   background results whose generation no longer matches.

6. **Set `AXUIElementSetMessagingTimeout` on every AX element (approximately 1 second).**
   An unresponsive app can leave `AXUIElementCopyAttributeValue` hanging indefinitely.
   **Without this timeout, one frozen Electron app can stall the entire switcher.**

7. **Filter windows by `kCGWindowLayer == 0`, not by size.** For windows set aside by
   Stage Manager, `kCGWindowBounds` reports the small, tilted rectangle in the left
   strip. Size filtering would discard them all without an explanation for the user.

8. **`Window` is an immutable struct; snapshots are immutable arrays.** The main thread
   reads the old snapshot while a background thread builds the new one, then replaces
   it as a whole when publishing. This is **inherently lock-free**. Do not introduce
   shared mutable state.

9. **Document allowed degradation**: while Secure Input is active, such as in a password
   field, the system does not deliver events to the tap. ⌘+Tab automatically uses
   native behavior. This is **expected behavior**, not a bug.

---

## Rule 5: Local environment pitfalls

- **Only CommandLineTools is installed, not full Xcode.** Instruments and the view debugger
  are unavailable. Build with `swift build` and manually assemble the `.app` bundle
  (`scripts/build-app`), rather than using an Xcode project.
- **Accessibility permissions depend on code signing.** With ad-hoc signing (`codesign -s -`),
  the hash changes on every rebuild, requiring **permissions to be granted again in
  System Settings after every rebuild**. Use a self-signed certificate to keep the
  designated requirement stable. **This is not optional**: it directly affects iteration speed.
- **Restart the app after granting permissions for them to take effect.** If permission
  changes appear ineffective, check this before investigating the code.
- **Screen Recording is the second TCC permission** (since 0.0.3). Like Accessibility,
  it is tied to code signing and requires an app restart after granting access.
  **slime must remain usable without it**: cards fall back to app icons, without blocking
  startup or exiting. This is a hard requirement; see spec §6.
- This machine uses a Clash Verge proxy at `http://127.0.0.1:7897`. If terminal commands
  such as `git push`, `gh`, or `curl` cannot reach GitHub, **export these variables and retry first**:

  ```sh
  export http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897
  ```

  **Do not assume the network is broken**: the symptom is a timeout, but the cause is a missing proxy.
- **Swift 6 language mode** (the tools 6.0 default) deliberately deviates from the Swift 5
  lock in spec §13. XCTest is unavailable locally, while swift-testing ships with the
  Swift 6 toolchain. Using Swift 6 lets tests run without full Xcode. The tradeoff is
  strict concurrency in AppKit code (`@MainActor` and a few documented
  `@unchecked Sendable` uses). See `docs/modules/app/decision.md` for the rationale
  and conditions for revisiting this choice.
- Generated artifacts (`.build/`, `build/`) are not committed.

---

## Rule 6: Code layers

```
Sources/slime/
  App/        main.swift, AppDelegate.swift, Permission.swift
  Core/       Window.swift, Search.swift, Trigger.swift, GridLayout.swift
  System/     EventTap.swift, WindowEnumerator.swift, WindowCache.swift, WindowActivator.swift,
              AppIcons.swift, Settings.swift, WindowThumbnails.swift
  UI/         PanelWindow.swift, PanelController.swift, CardGridView.swift, SettingsWindow.swift
Tests/slimeTests/
docs/         specs / modules / templates
scripts/      build-app, test, hooks/
```

### Allowed imports

```
App/      →  UI, System, Core
UI/       →  System, Core
System/   →  Core, AppKit, CoreGraphics, ApplicationServices, ScreenCaptureKit
             Sparkle only in AppUpdater (signed update delivery)
Core/     →  Foundation, standard library
             ✗ AppKit, CoreGraphics, ApplicationServices, ScreenCaptureKit are forbidden
```

**`Core/` is the pure logic layer.** It is the only part of this project that can be
unit-tested; the restriction is practical. Once the `Trigger` state machine can import
AppKit, someone will reach for `NSEvent` inside it, and tests can no longer exhaustively
check the risk of swallowing the wrong keys and breaking the keyboard system-wide.

The public interfaces of `Trigger` and `Search` must be pure functions:

```swift
func reduce(_ state: State, _ event: Event) -> (State, [Effect])
```

**Translate CGEvent / NSEvent in `System/` and `UI/`, not in `Core/`.**

### Create directories when needed, not as empty scaffolding

| Location | When to add content |
|---|---|
| `docs/modules/<module>/` | The module exceeds 150 lines or has correctness assumptions |
| New files under `Sources/slime/System/` | An actual new system boundary appears |
| Layering guard tests | When `Core/` reaches four files; **already implemented** in `Tests/slimeTests/LayeringTests.swift`, which blocks AppKit / CoreGraphics / ApplicationServices imports in Core/ |

**Keep the source-file count small (18 in 0.0.3).** Before adding a file, ask whether
its contents fit in an existing one.
