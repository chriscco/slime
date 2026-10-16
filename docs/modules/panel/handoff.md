# Panel handoff — 2026-10-16

The preview-source preference is bilingual in Appearance and defaults to cached previews.
Panel open starts a fresh thumbnail session; every hide path ends it. Reopening clears
reused cards immediately even if rows are unchanged. Source changes invalidate old results.
The 300 ms first-frame deadline, selection/search flow, and proportional image layout remain.
Native screenshots remain serial; cards update when that batch returns, not after each screenshot.

Tests exercise the real Appearance popup action and saved preference, plus session image
clearing, closed-panel capture suppression, stale completions, and 10/50/100 request counts.
Tests that mutate the global thumbnail owner or instantiate PanelController share a serialized
suite so async close/capture operations cannot interleave fixture state.

Native read-only capture proved a useful perspective image; see the system handoff. No
physical-shortcut, multiple-display, or native panel responsiveness acceptance is claimed.
The release benchmark measures CPU query/layout/offscreen painting only.
