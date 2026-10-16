# App handoff

Updated 2026-10-15. Branch: `feat/0.0.7`. Issue: [#61](https://github.com/chriscco/slime/issues/61).
Spec and implementation share one PR; the user performs the merge.

## Current state

0.0.6 has been published. Its native/performance limitations and release evidence remain
in [the validation record](../../releases/0.0.6-validation.md) and #52.

0.0.7 adds persisted Black, White, Deep Blue (#0A2C37), and System backgrounds.
Black remains the default. System inherits application appearance, and effective
appearance callbacks refresh cached colors without changing query, focus, or selection.
Glass strength still controls mask opacity; at full transparency no base color remains.

Settings shows four static, keyboard-accessible preview buttons in a two-column grid.
The body scrolls inside the original window dimensions. A rounded bundled slime icon
aligns with search and the preview inset. A plain ⌘F hint yields to focus or close
status text. Placeholder and query use semantic primary text in both appearances.
Theme preview buttons use a full rectangular native cell hit region; the previous
borderless radio cell returned no trackable area despite performClick tests passing.
No new thumbnail capture, AX operations, polling, or continuous animations were added.

## Verification and next steps

See [0.0.7 validation](../../releases/0.0.7-validation.md) for exact checks and gaps.
Run `scripts/test` and `scripts/build-app`; restart the rebuilt app for native keyboard
acceptance. Permission behavior and public AX limitations are unchanged.

Review and merge the combined spec/implementation PR after native acceptance.
0.0.7 is not tagged or published by this change. A later release must build from the
merged commit and explicitly complete the release gates; the existing 0.0.6 DMG remains.

## 2026-10-16 header alignment follow-up

The shortcut hint now sizes to its native 15 pt text height before centering, replacing
a 20 pt box that made the glyphs sit high. Logo width/height share the search-row
height directly. Tests confirm a 32 pt image drawing rect and field height; the
reported visible logo-height mismatch remains unreplicated and needs a screenshot
from the running app (including whether search is focused). All 178 tests pass.
