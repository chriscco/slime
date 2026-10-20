# Trigger handoff — 2026-10-20

0.1.0 retains one pure reducer and adds a held-modifier `typing` state. Releasing
after compatibility text or explicitly focusing search enters native editing.
`queryChanged` replaces the complete query, and identical strings do not reset
selection. Enter asks the panel to activate; only a real target ends the session.

The tap copies and swallows key packets only during focus handoff (64 packets,
2 seconds) and for reserved Command/Option-Tab. Focus must be acknowledged by the
actual key panel and SearchEditor responder. The deadline must not reset when a
batch drains before acknowledgment. After handoff, ordinary keys, modifiers and
releases reach AppKit naturally; Control-Space remains available throughout.

Queued effects/packets capture the tap revision; editor commands capture the panel
session. Preserve swallowed press/release pairing and existing native fallback.
No UI, AX, locks or I/O belongs in the tap callback.

Regression tests cover the handoff bounds, stale events and reserved Tab. All
deadline reads share one monotonic uptime source; tests control it so unrelated
MainActor work cannot accidentally expire packets. Production uses system uptime. Full
physical global-gesture acceptance remains pending; see the
[validation record](../../validation/2026-10-20-chinese-search.md). Do not infer it
from direct native-panel fixtures or reducer tests.
