---
name: Task
about: Define a bounded, verifiable change
title: ""
labels: ""
assignees: ""
---

## Goal

<!-- One sentence on what will happen once this is done. -->

## Why

<!-- The problem, evidence, or root cause; don't just write the proposed solution. -->

## Scope

Do:

- <!-- deliverables -->

Not doing:

- <!-- explicit exclusions -->

## Acceptance criteria

<!--
Every item must be decidable by a test, a command, or a concrete observation.
For the window switcher, spell out what is pressed in what state, e.g.
"Hold ⌘, tap Tab once, release ⌘ — the frontmost window is now the highlighted one."
Don't write undecidable things like "switching feels smooth".
-->

- [ ] <!-- executable acceptance item -->

## Test seam

<!--
Which public interface do we observe the behavior through? `Trigger` and `Search` go through
`Tests/slimeTests/`; anything involving real permissions or WindowServer (enumeration, AX, panel,
activation) writes "manual acceptance, see the issue's acceptance criteria". Pure documentation
tasks write "N/A".
-->

## Constraints & links

<!--
Related specs, issues, or compatibility that must be preserved.
If this touches any red line in CLAUDE.md section 4, name which one here. If none, write "None".
-->
