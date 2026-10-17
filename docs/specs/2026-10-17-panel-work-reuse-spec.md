# Reduce redundant panel work (0.0.8)

Issue: #83. This implements the approved performance-audit recommendations and the subsequently approved immediate-placeholder presentation flow.

## Behavior

- Title-only focus notifications update the list immediately without warming every app icon or requesting another preview batch. Actual window focus changes, completed enumeration, and window removal keep their preview refresh behavior.
- Cached disk pruning runs on the first snapshot after a preview-source reset and when live window IDs change, not for every title/order refresh. Existing pending capture deduplication, cancellation, ownership tickets, and background Stage Manager snapshots remain intact.
- Cards filtered out by search are detached but reusable for the full accepted window list during that panel session. A result restored by deleting query text keeps its view identity and receives current title/preview data.
- Removed windows and changed owners invalidate pooled views. Dismissal releases detached cards. Existing visible cards can remain in the hidden panel as before; no cross-session detached-view cache is introduced.
- Show the panel immediately with default window illustrations, app icons, titles and selection. Missing previews must not block keyboard input. Completed captures update the existing cards progressively without changing their identity, size or selection; failed captures keep their placeholder.
- Both sources retain the last successful in-memory preview across panel sessions. Fresh still reads/writes no thumbnail files and accepts tilted Stage Manager captures; Cached preserves normal offscreen previews. Source changes reset images. Capture remains serial; bounded concurrency is not included.
- Refresh changed focus identities (current and previous), titles and visibility, leaving other previews intact. Repeated identical snapshots/openings do not recapture the whole list. On a later warm call, retry the current onscreen window after one second and other onscreen windows after 30 seconds; there is no new timer. These are attempt intervals, so failures are bounded too.
- Fresh cancels unfinished work on dismissal but retains completed images; hidden snapshots still evict removed/replaced owners and record changes for the next open. Failed refreshes retain the last successful image. New or never-captured windows use placeholders.
- Before the first window snapshot, show a localized loading message; distinguish a completed empty snapshot from loading, and preserve queries typed before the list arrives.
- Reject invalidated partial and final images after removal, owner replacement, Fresh dismissal or preview-source changes; completed retained images survive reopening. Do not let screenshot completion reopen a hidden panel. Refresh images deferred during CRT after closing completes.
- A queued save can arrive after a newer prune. If a completed save includes no-longer-live IDs, invalidate prune memoization so the next unchanged snapshot cleans the late file.
- Keep accessibility, close animations, selection ordering, and current-window semantics unchanged.

## Opening-latency boundary

The audit's 1.9 ms cached show time is not physical key-to-photon latency. The old Fresh path waited for capture settlement or 300 ms and measured 196–315 ms. The user approved removing that presentation gate: both sources now show available content/placeholder cards immediately and fill previews progressively. This makes presentation independent of slow capture completion; it does not make screenshot generation instantaneous or establish a physical display-latency guarantee.

## Verification

- Public controller tests narrow/broaden search, remove filtered windows, replace owners, and dismiss sessions; observe card identity/lifetime and rendered data.
- Cache callbacks distinguish title-only events from focus/snapshot refreshes.
- Injected thumbnail disk operations count first/change/reset pruning and unchanged-membership deduplication; existing stale-image and persistence tests remain green.
- Repeat the release component benchmark on the same 10/50/100/300 synthetic inputs and report scoped CPU timing, not display latency.
- Run scripts/test. Native physical-event and frame-presentation timing remain outside automated coverage.

Additional tests cover immediate presentation with pending captures, first-result publication before batch completion, placeholder layout stability, stale partial results, cold-list loading/search and late-save prune invalidation.

The retained-preview follow-up supersedes the original per-session Fresh image lifetime in the 0.0.8 preview-source spec. Settings must explain memory reuse and the no-disk/tilted-capture distinction. Tests cover repeat openings, selective focus refresh, metadata/visibility transitions, bounded fallback attempts, hidden removal and cancelled refreshes preserving old images.
