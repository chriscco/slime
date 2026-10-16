# Window switching validation — 2026-10-16

Issue #79; baseline preview branch `31b70db`. Host: Apple M4, 16 GiB,
macOS 27.0 (26A428), signed release builds. This record distinguishes native
observations from automated tests and does not claim physical input latency.

## Native diagnostic evidence before the fix

The authorized baseline app enumerated two Warp CG window IDs while AX exposed only
one standard window. Its live AX title differed from the matching CG name. Chrome
had three CG windows with identical frames, while AX exposed one standard window
and two unknown helper elements; its standard window title differed from all three
CG names. These observations rule out choosing the first frame match or treating
CG names as necessarily current. Diagnostics stored title equivalence groups only;
no user window titles or screenshot content are committed.

A retained AX identity is learned while a window is discoverable and kept only for
its accepted CG ID/PID. Previously unseen offscreen targets can still lack an exact
mapping. The approved fallback activates the application without a popup or retry.

## Process measurement

Sample `proc_pid_rusage` every 250 ms, convert CPU ticks using `mach_timebase_info`
(125/3 on this host), and report physical footprint rather than RSS. CPU 100% means
one core. WindowServer/GPU and other applications are excluded. Foreground activity
and preview-source preferences are held as observed; these are short native samples,
not a statistical guarantee or physical keyboard-to-screen latency measurement.

| Build / state | Duration | Average CPU | Peak physical footprint |
|---|---:|---:|---:|
| Baseline, settling after launch | 30.14 s | 0.331% | 19.03 MiB |
| Baseline, stable idle | 30.19 s | 0.000% measured | 18.99 MiB |

No CPU counter increase was measured during the stable baseline interval; this does
not establish zero overhead for arbitrary workloads. The `b26cb52` signed release build was sampled three times with the panel closed:

| New build / interval | Duration | Average CPU | Peak physical footprint |
|---|---:|---:|---:|
| First interval | 30.19 s | 0.582% | 18.89 MiB |
| Second interval | 30.23 s | 0.504% | 19.03 MiB |
| Third interval | 30.00 s | 0.400% | 19.39 MiB |

A separate two-second native stack sample found the main thread waiting for events and
occasional existing EventTap character translation; it did not sample observer/enumeration
activity. The desktop was not input-isolated, so these intervals are **not** a controlled
idle regression comparison, nor proof that the observer adds 0.4–0.6% CPU. They establish
approximately 19 MiB footprint and low process CPU under the observed desktop activity.
No periodic refresh was added; tests cover event coalescing and stop cancellation.

## Automated and build checks

- Full `scripts/test`: 215 tests, including partial AX-list ambiguity, cached native
  identity, fallback without raise, PID/ID rejection, focus/title updates, coalesced
  observer reads, external-focus/input cancellation and monitor cleanup, MRU and stable grouped panel sessions.
- Signed release bundle built with `CONFIG=release REQUIRE_SIGNING=1 scripts/build-app`.
- Switching does not call CG/AX window enumeration or capture. The direct target path
  has one unminimize, one raise, and one focused-window read, with request checks between
  calls. This operation count is not a measured physical latency guarantee.

## Native acceptance still required

- Owner confirmed window switching is correct after visiting the Warp windows.
- **Still failing:** owner confirmed the Chrome card reaches the expected window but retains its old title after switching tabs. Redacted native diagnostics show the stale card has no mapped native target; app-only fallback activates a different accepted CG identity whose fresh AX title is already displayed correctly. The stale card remains offscreen. This is an unresolved candidate-liveness/identity issue, not evidence that the title observer missed the live window update.
- Switch windows within one app outside slime; verify current first, previous selected.
- Rapidly switch twice; verify a delayed old request does not steal final focus.
- Verify same-title/Stage Manager/minimized/other-Space windows retain safe fallback.

No real user document is closed for these checks. Unit tests and process measurements
cannot certify native multiwindow/Space behavior by themselves.

### Follow-up native title diagnosis

The owner selected the stale-title card, changed an existing Chrome tab, and reopened
the panel. The redacted sample contained three accepted Chrome CG IDs: one onscreen
with a retained AX target and a fresh AX title, and two offscreen without native targets.
The reported stale-title card was one of the unmatched offscreen candidates. Selecting
it used application fallback and reached the onscreen identity; it did not demonstrate
exact switching to the stale candidate. Do not copy that foreground title onto the
unmatched card or infer closure solely from an incomplete AX list. The actual count of
independent Chrome windows is awaiting owner confirmation before changing admission.
Temporary probe source is removed; no user browsing content is committed.
