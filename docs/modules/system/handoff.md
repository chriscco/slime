# System handoff — 2026-10-16

Preview-source implementation for issue #72 is isolated from settings/updater issue #73.
Shared requirements: [0.0.8 spec §B](../../specs/2026-10-16-slime-0.0.8-spec.md#b-preview-source-preference).
Cached mode stays default; fresh sessions bypass disk and accept nonblank perspective images.
Captures/persistence are gated by current identity tickets; cancellation never blocks on I/O.
An already-started file operation can finish after a source change; this is not cache erasure.

Native read-only experiment on macOS 27.0 (26A428) had Screen Recording permission. Sampling six
visible and six offscreen layer-zero candidates over 100 points per dimension produced:
- visible: two ordinary usable images, two nonblank transparent-corner images, two blanks;
- offscreen: three transparent results, two SCK -3811 failures, one solid-color image.

A temporary transparent-corner sample was visually inspected: recognizable tilted two-pane
application content, preserved by fresh validation and rejected by cached validation.
Repeated probe successful screenshot calls ranged roughly 19–308 ms, with compilation/load
varying between runs. No window titles or image artifacts are committed. No app activation,
window movement, minimization, or Space changes were performed.

This does not verify each sample's exact Stage Manager/minimized/other-Space state, multiple
displays, physical panel input-to-display latency, or user-perceived smoothness. Those remain
native owner acceptance before release; public SCK cannot guarantee every window's output.
Synthetic tests cover 10/50/100 windows with exactly N requests after ten repeated warm calls.

Release CPU query/layout/offscreen-paint benchmark (30 samples, milliseconds):

| Windows | Ungrouped p50 / p95 | Grouped p50 / p95 |
|---|---|---|
| 10 | 32.47 / 89.82 | 31.63 / 46.69 |
| 50 | 34.93 / 51.24 | 36.68 / 59.31 |
| 100 | 47.09 / 59.15 | 33.73 / 57.10 |

These are current-checkout measurements during local build activity, not native panel latency
or a controlled performance improvement claim. Capture requests remain exactly 10/50/100
in fresh-mode tests after ten repeated snapshot warm calls; no live video loop was introduced.

Actual process CPU/footprint and a native 11-window panel/search harness are recorded in
[0.0.8 performance validation](../../validation/2026-10-16-slime-0.0.8-performance.md).
The instrumented workload showed 12/12 visible panel cycles per mode, 3/11 cached and 8/11
fresh accepted images, ~8.98% / 10.59% active CPU, and ~30.88 / 35.03 MiB peak footprint.
Both recovered below 0.03% average CPU. Values include the required Mach timebase conversion;
WindowServer/GPU cost and physical event-tap latency are excluded. Native matrix gaps remain.

Review follow-up: queued warm tasks validate tickets before starting disk loading. Disk-read
jobs are tracked/cancelled with captures; cancellation propagates to detached reads and stops
between files. A read/write/delete already underway can finish, without a main-thread barrier.

## Same-title offscreen admission follow-up

Owner-approved rule: if the same PID has a confirmed live window with the same
nonempty title, discard unconfirmed offscreen candidates and their stale known
entries. `KnownWindow.observedOnscreen` persists manual onscreen discovery alongside
standard AX/minimization evidence. Two-pass filtering is independent of CG order.
Unseen genuine same-title windows on another Space may need one manual visible
visit; the owner explicitly accepted this boundary. Screenshot validity is not used
as window-identity evidence. No app-specific names, sizes, or private APIs are used.
Regression coverage includes stale caches, enumeration order, confirmed/minimized
siblings, different PIDs/titles, manual discovery followed by offscreen retention,
and serialization of the new optional field. The owner subsequently confirmed the duplicate cards are gone in both preview modes.

## Responsive window switching (#79)

The new branch is stacked on #75. Native targets are retained in System and used directly
for bounded off-main activation; application fallback happens immediately without full
window enumeration. Foreground focus/title events maintain window MRU and card/search text.
The current window comes first; the panel initially selects the previous identity and keeps
existing order stable while open. The observer is explicitly stopped when disabled.

Native diagnostics and baseline process measurements are recorded in
[window switching validation](../../validation/2026-10-16-window-switching.md).
Warp's incomplete AX list and Chrome's identical CG frames/stale names were observed;
actual post-change multiwindow switching/title behavior still needs native acceptance.
Do not infer exact native behavior from injected activation tests. Keep the immediate
application fallback for targets that public AX cannot yet identify.

## Reopening after Escape with a held modifier

Idle Tab events recover Command/Option from CGEvent flags, because dismissal ends
the session without generating another modifier-down event. The callback still
checks disabled/degraded state first; active sessions retain their current mode.
The callback regression failed before the fix and all 212 tests pass afterward.
Native keyboard acceptance remains pending; no AX work or waiting was added.

## 2026-10-17 — Background work audit follow-up (#83)

Split list publication from preview refresh and deduplicate cached disk pruning by live IDs. Tests cover title bursts, real focus, closing, membership changes and preview-source resets. No change to AX identity validation or capture concurrency. The user's stored source was Fresh during latency investigation; the former 300 ms presentation wait has now been removed by user approval. Partial images keep the same session/owner validation. Late saves invalidate prune memoization after completion.

## 2026-10-17 — Retained previews (#84 follow-up)

Supersedes the earlier per-session Fresh clearing described above. Both sources now retain successful memory images on reopening. Fresh keeps no disk previews, cancels unfinished captures on hide, and still accepts tilted Stage Manager images. Warm reconciles hidden removals and prioritizes changed focus/title/visibility. Unchanged onscreen windows are eligible after one second for the current window or 30 seconds for others, checked only on existing warm events; no timer. Failures retain old images. Settings and README explain the updated lifetime.
