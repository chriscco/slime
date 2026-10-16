<!--
A PR description that only says what changed has no value — the diff already says it.
Write what the diff can't show: why, what was cut, and how you verified it.
-->

<!--
Every PR must link an issue. Don't mix up the two forms (CLAUDE.md section 2):
  Closes #N  — the deliverable is **done**; merging closes the issue automatically
  Refs #N    — only part of it is done (e.g. a spec only); links without closing
Using Closes wrong closes an unfinished issue, and then it disappears from the todo list.
-->
Closes #

## Why this change

<!-- The essence of the problem. If it's a bug, state the root cause, not just the symptom. -->

## What changed

<!-- One or two sentences. Don't restate what the diff already shows. -->

## What was cut

<!--
The KISS/YAGNI cost must be spelled out: which corner was cut, where the limit is, when it needs filling in.
The matching `shortcut:` comment sits in the code. If nothing was cut, write "None" —
but first make sure this really isn't over-engineering.
-->

## How it was verified

<!--
State the local `scripts/test` result, and the public behavior the new tests cover.
For behavior that needs a real machine (shortcuts, permissions, Stage Manager), write how you
verified it by hand — this step can't be skipped.
-->

## Checklist

- [ ] Not committed directly to main
- [ ] Behavior changes follow red → green and are tested through public interfaces; pure docs/static config write "N/A"
- [ ] `scripts/test` passes locally
- [ ] The link matches the delivery: merged PRs are complete and use `Closes #N`; partial work uses `Refs #N` and is not merged
- [ ] If any red line in CLAUDE.md section 4 is touched, each was checked off and named under "Why this change"
- [ ] No new AppKit / CoreGraphics / ApplicationServices imports in `Core/`
- [ ] If a documentation threshold is met, spec / design / decision are updated (see CLAUDE.md section 3)
- [ ] This PR updates the current unreleased version’s notes with one English entry, its PR link, and its author’s GitHub username; frozen notes remain unchanged (see `docs/releases/README.md`)
