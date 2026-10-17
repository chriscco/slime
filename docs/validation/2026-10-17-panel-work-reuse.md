# Panel work reuse validation

Baseline: `1701c3d`. Implementation: #84 (`4aa7d1c` code changes). Host: Apple M4, 16 GiB, macOS 27.0 (26A428). Release builds, solid offscreen panel, synthetic windows and placeholder previews.

## Repeatable benchmark

Run from the implementation branch so both revisions use the same updated fixture:

```sh
scripts/benchmark 1701c3d
scripts/benchmark
```

`search_restore` filters to zero matches and removes the query, through the actual controller. Five warmups precede 20 samples. Timings include UI update CPU work, not physical keyboard input, WindowServer composition, or display latency.

| Windows | Grouped | Before median / p95 (ms) | After median / p95 (ms) |
|---:|:---:|---:|---:|
| 10 | No | 2.39 / 6.80 | 1.32 / 6.58 |
| 10 | Yes | 2.60 / 8.99 | 1.65 / 7.57 |
| 50 | No | 7.69 / 11.39 | 3.33 / 9.94 |
| 50 | Yes | 11.44 / 20.82 | 4.07 / 9.57 |
| 100 | No | 17.12 / 20.06 | 5.30 / 12.87 |
| 100 | Yes | 18.13 / 23.59 | 8.16 / 13.89 |
| 300 | No | 58.46 / 65.37 | 16.54 / 18.26 |
| 300 | Yes | 87.38 / 98.39 | 24.35 / 26.52 |

The previous audit harness was also repeated: its 100-window medians fell from 17.06/19.70 ms to 5.29/6.88 ms, and 300-window medians from 58.11/86.51 ms to 17.11/23.59 ms (ungrouped/grouped). Different fixtures and sampling runs should not be mixed into a single speedup claim. The tracked benchmark above is the reproducible comparison.

The gain is largest when restoring many filtered cards. Tab remains below 0.3 ms median at 300 windows in these component runs. No claim is made that normal 10-window keyboard input is perceptibly faster or that these measurements establish new process-wide CPU/memory percentages.

## Regression checks

- 235 Swift tests passed. 18 Python script tests passed.
- The search test first failed because the restored card had a new identity. It now verifies reuse, current title, removal, owner replacement both visible and filtered, and release of detached cards after dismissal.
- The title-burst test first requested four full preview refreshes for the initial snapshot plus three titles. It now requests one; real focus and close still trigger refresh callbacks.
- The disk-pruning test first issued 22 prune operations for the initial snapshot, 20 unchanged/reordered snapshots and one removal. It now issues two, then another after a preview-source reset. Existing capture deduplication/persistence/cancellation tests remain green.
- Existing observer Sendable warnings were not addressed by this scoped change.

## Original opening-latency diagnosis (before progressive presentation)

The user's saved `preview.source` was `fresh`, confirmed read-only on this machine. The original `PanelController.show` started new captures and waited for settlement or the 300 ms deadline before ordering the panel front. The prior real-window runs measured median 196 and 315 ms, depending on capture duration. That is consistent with a short visible delay and is not covered by the 1.9 ms warm-cached measurement.

The trigger reducer emits `showPanel` on the first Tab without a delay timer. EventTap asynchronously delivers it to the main queue; the panel already disables the default window entrance animation. This inspection does not quantify the system's physical event delivery, main-queue stalls during arbitrary desktop activity, or presentation to the display. No real hardware keypress trace was captured in this change, so Fresh is a strong explanation, not a claim that all end-to-end delay has been isolated.

Cached mode can also wait when previously uncached windows are pending. The initial two optimizations did not change presentation. The subsequent user-approved update now presents placeholders immediately and streams screenshots; its validation is recorded below. To resolve any remaining cached-mode delay, the next measurement must correlate a real Tab event timestamp, event-tap callback, main-handler entry, order-front call and presentation evidence on the same run.

## Immediate presentation and progressive previews

The follow-up removes the screenshot settlement/300 ms presentation gate for both preview sources. Existing placeholders show the window illustration, app icon, title and selection; completed captures replace images in place. Fresh remains session-only and capture remains serial.

A disposable release-build harness used the actual panel and ScreenCaptureKit with 12 real window candidates and the existing glass appearance. It invoked the controller directly, with no physical keyboard event. All three openings returned with a visible panel and 12 placeholders:

| Opening | Show call (ms) | First image callback (ms) | Capture observation |
|---|---:|---:|---|
| First process opening | 48.53 | 284.35 | Images were cleared before sampling; excluded from completion comparison |
| Second | 7.20 | 104.07 | 8 previews; settled by 331.50 ms |
| Third | 7.65 | 209.83 | 8 previews; settled by 438.54 ms |

The first run's cleared images indicate an interrupted session; this harness does not identify the cause. These three samples establish that presentation no longer waits for screenshots, not a stable latency distribution or key-to-photon result. Screenshot duration still varies with desktop activity. The first process opening also retains AppKit/window initialization cost. No screenshot concurrency changes were made.

- 242 Swift tests pass, including immediate Fresh/cached presentation, cold loading versus empty list, typing before the first snapshot, progressive card identity/frame/selection preservation, failed captures, stale progress after session/owner/source changes, and previews received during CRT closure.
- Reviewer comment `6228625318`: a delayed disk save can arrive after pruning. Its completion now invalidates the pruning memo when it writes a no-longer-live ID, allowing the next identical snapshot to prune again. A deterministic regression reproduces save-after-prune ordering and verifies the second cleanup.
- Both the presentation and late-save tests failed before their respective implementation changes.
