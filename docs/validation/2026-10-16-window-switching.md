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
not establish zero overhead for arbitrary workloads. New-build results follow after
implementation and signed-build verification.

## Native acceptance still required

- Visit both Warp windows, then select each card and verify the exact target.
- Switch/close Chrome tabs and confirm current card and search titles update.
- Switch windows within one app outside slime; verify current first, previous selected.
- Rapidly switch twice; verify a delayed old request does not steal final focus.
- Verify same-title/Stage Manager/minimized/other-Space windows retain safe fallback.

No real user document is closed for these checks. Unit tests and process measurements
cannot certify native multiwindow/Space behavior by themselves.
