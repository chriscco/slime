# Reduce redundant panel work (0.0.8)

Issue: #83. This implements the two approved performance-audit recommendations. Fresh capture presentation is deferred.

## Behavior

- Title-only focus notifications update the list immediately without warming every app icon or requesting another preview batch. Actual window focus changes, completed enumeration, and window removal keep their preview refresh behavior.
- Cached disk pruning runs on the first snapshot after a preview-source reset and when live window IDs change, not for every title/order refresh. Existing pending capture deduplication, cancellation, ownership tickets, and background Stage Manager snapshots remain intact.
- Cards filtered out by search are detached but reusable for the full accepted window list during that panel session. A result restored by deleting query text keeps its view identity and receives current title/preview data.
- Removed windows and changed owners invalidate pooled views. Dismissal releases detached cards. Existing visible cards can remain in the hidden panel as before; no cross-session detached-view cache is introduced.
- Keep accessibility, close animations, selection ordering, and current-window semantics unchanged.

## Opening-latency boundary

The audit's 1.9 ms cached show time starts inside PanelController and ends when the order-front call returns; it is not physical key-to-photon latency. The user's stored preview source is Fresh, which waits for fresh capture settlement or a 300 ms deadline. Measured fresh show medians were 196 and 315 ms. This is a likely major contributor, not a reproduced attribution of every physical keypress. Do not change that policy in this PR or claim these optimizations eliminate it.

## Verification

- Public controller tests narrow/broaden search, remove filtered windows, replace owners, and dismiss sessions; observe card identity/lifetime and rendered data.
- Cache callbacks distinguish title-only events from focus/snapshot refreshes.
- Injected thumbnail disk operations count first/change/reset pruning and unchanged-membership deduplication; existing stale-image and persistence tests remain green.
- Repeat the release component benchmark on the same 10/50/100/300 synthetic inputs and report scoped CPU timing, not display latency.
- Run scripts/test. Native physical-event and frame-presentation timing remain outside automated coverage.
