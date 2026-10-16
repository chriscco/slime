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
