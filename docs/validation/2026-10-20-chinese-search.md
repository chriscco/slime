# 0.1.0 Chinese search validation

Scope: [approved spec and grilling revision](../specs/2026-10-20-slime-0.1.0-spec.md), [PR #103](https://github.com/chriscco/slime/pull/103).

## Environment

- Development system: macOS 27.0.1, build 26A434.
- Required input methods, confirmed by the owner: macOS built-in Pinyin and Rime.
- Installed Rime bundle: `/Library/Input Methods/Squirrel.app`, identifier
  `im.rime.inputmethod.Squirrel`, `CFBundleVersion` 1.1.2. This installation also
  contains TriFectaSettings; stock Rime behavior must not be assumed.
- System Settings → Keyboard → Text Input → Edit visibly lists ABC, 简体拼音
  and 鼠须管、鼠须管. The earlier command-line preference snapshot omitted Rime;
  the live settings UI confirms it is configured. No settings were changed.

## Automated checks

- `scripts/test`: 274 tests pass, including native AppKit tests, tap handoff bounds,
  stale delivery, full-query filtering, clipboard/undo and composition cancellation.
- `python3 -m unittest discover -s scripts/tests`: 17 tests pass.
- `CONFIG=release scripts/build-app`: passes, self-signed `build/slime.app`.
- `git diff --check`: passes.

Independent source review found two handoff defects (deadline reset before focus
acknowledgment and reserved modified Tab falling through to the OS). Both were
fixed with observed failing/passing regression tests. Desktop testing then found
empty marked-text cancellation failed to publish the final empty query; that was
also reproduced in a regression, fixed and retested on both actual input methods.
The final source review reported no remaining concrete correctness blockers.

## Desktop evidence

The temporary validation app compiles the production panel/editor/controller and
uses four fake window identities: 测试—工作周, 测试—工作计划, 微信—聊天, and
Browser—Example page. A regular control window opens the production nonactivating
panel. The fixture uses a local reducer callback and **does not install EventTap**.
Activation records the selected identity instead of activating a real window.
These checks therefore establish native editing behavior, not end-to-end global
switching. The fixture is outside the repository and has been quit.

Input-source IDs were recorded alongside committed-query events:
`com.apple.inputmethod.SCIM.ITABC` and `im.rime.inputmethod.Squirrel.Hans`.
Physical Control-Space switched between them without dismissing the open panel.
The fixture's explicit source-selection buttons sometimes dismissed the panel
while selecting the source immediately after opening; reopening with that source
already active worked. This setup behavior is not a production verdict.

| Check | Observed result |
| --- | --- |
| System Pinyin: type `gongzuo`, Space | Marked `gong zuo` retained all four rows; committed 工作 produced two rows. |
| System Pinyin: append `zhou`, Escape | 工作 remained and the panel stayed open. |
| System Pinyin: select all, `zhou`, Space | Replaced query with 州 and showed no results. |
| System Pinyin: undo / redo | Restored 工作 and then 州 with corresponding results. |
| No-results Enter | Panel and query remained visible. |
| Multiline paste | `工作\n周` became `工作 周`; no activation occurred. |
| Both IMEs: `gongzuo`, digit 1 | Committed 工作 and displayed the two matching rows. |
| Rime: `zhou`, Enter after 工作 | Committed native literal 工作zhou; the same Return did not activate a window. |
| Rime: composing `zhou` after 工作 | Existing two rows remained until commit. |
| Rime: click second card while composing | Recorded exactly window 990002, 工作计划, then dismissed. |
| Dismiss/reopen | Editor was empty and all four rows returned. |
| Both IMEs: select all, `a`, Escape | After the fix, empty editor published an empty query and all rows returned; the cancellation key did not dismiss. |
| Rime: native undo after commits | Restored earlier committed text and matching results. |

## Remaining acceptance / merge gate

Full acceptance is **not complete**. The following still need evidence using the
actual running application, with both required input methods:

- Command/Option trigger gestures, held-letter compatibility and first-key handoff;
- real candidate-window placement, mouse selection and navigation/partial commits;
- marked-text close/settings shortcuts, real activation/focus restoration and
  long-text mouse selection/scrolling;
- the remaining dismissal, refresh and fallback matrix in the spec.

The desktop tool could inspect the fixture but repeatedly timed out binding the
hidden accessory slime app. Restarting the newly signed build and sending
Option-Tab from Finder did not expose a verifiable slime surface through the tool.
The process remains running and the stored enabled setting remains true. This is
an automation limitation/unverified outcome, not evidence of successful global
switching. No accessibility permissions or persistent preferences were changed.

No macOS 15 desktop acceptance is claimed. Keep PR #103 draft and use `Refs #102`
until the required acceptance is completed; do not close the issue or mark the
release accepted based only on automated tests and this fixture.
