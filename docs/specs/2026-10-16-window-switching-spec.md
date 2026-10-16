# Precise, responsive window switching

Issue #79; stacked on preview PR #75. The owner approved this design and requested
implementation and spec together in a new PR.

## Behavior

- Target the selected native window, including two Warp/Chrome windows and same-title
  windows. Maintain usable AX identity in the background. Never choose an arbitrary
  first title match when more than one target is possible.
- The switch path does not perform full enumeration, capture, or a retry loop. Use
  the maintained target directly with bounded off-main-thread AX work. If unavailable
  or rejected, immediately activate the app. No error popup or blocking recovery.
- Distinguish an exact target result from app-only fallback. Do not promote the
  selected window in MRU merely because the application was activated; use actual
  focus evidence. Do not let a delayed older switch override a newer user action.
- Read fresh window titles independently of thumbnail caches. Chrome tab changes
  update the card/search title. Background focus/title/window events are coalesced;
  no new periodic polling or per-keystroke enumeration/capture.
- Without grouping: current window first, remaining windows in window-level MRU.
  Observe external focus changes, including switching within one app.
- With grouping: current app group first, remaining groups by most-recent member;
  windows within each group retain window MRU. Initial highlight remains the previous
  window (not necessarily the second card when grouped). One-window panels select it.
- Preserve open-session order and selected identity on background refresh. Titles,
  removals, and newly discovered windows may update; append newcomers without
  reordering existing cards. Search remains relevance-ranked with stable tie order.
- Retain #75 duplicate-filter boundaries, all-window visibility, close safety,
  reduced-motion behavior, and the 300 ms panel presentation bound.

## Performance and verification

No synchronous AX IPC in the input callback/main thread. Bound target operations;
background bookkeeping must not block fallback or create idle polling. Explicitly
manage observer registration/removal and prevent stale completions.

Test exact/ambiguous/stale targets and fallback accounting; title-source changes;
external/per-window MRU; grouped initial selection; session-stable ordering and
search/removal behavior; observer/coalescing lifecycle and request counts. Run all
Swift tests and signed release build. Measure code-path costs separately from
physical input-to-display latency. Native Warp/Chrome and title-change acceptance
remains explicit until observed; do not infer it from unit tests.
