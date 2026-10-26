# Panel handoff — 2026-10-16

The preview-source preference is bilingual in Appearance and defaults to cached previews.
Panel open starts a fresh thumbnail session; every hide path ends it. Reopening clears
reused cards immediately even if rows are unchanged. Source changes invalidate old results.
The panel now presents app-icon placeholders immediately; selection/search flow and proportional image layout remain.
Native screenshots remain serial; cards update when that batch returns, not after each screenshot.

Tests exercise the real Appearance popup action and saved preference, plus session image
clearing, closed-panel capture suppression, stale completions, and 10/50/100 request counts.
Tests that mutate the global thumbnail owner or instantiate PanelController share a serialized
suite so async close/capture operations cannot interleave fixture state.

Native read-only capture proved a useful perspective image; see the system handoff. No
physical-shortcut, multiple-display, or native panel responsiveness acceptance is claimed.
The release benchmark measures CPU query/layout/offscreen painting only.

## Window switching follow-up (#79)

The cache supplies current-first window MRU. Initial selection follows the previous
window ID even when grouping places it later. Existing card order is stable during
an open session; updated titles/removals apply and new windows append. Search remains
relevance-ranked. As a result, a search or newly appended window can create a repeated
app section; each contiguous app run gets its own heading. Reopening restores full
MRU grouping. No extra capture or enumeration is triggered by navigation/search.

## 2026-10-17 — Search reuse and opening latency (#83)

Search now reuses detached cards, with tests for title updates, closed-window eviction, changed owners, and dismissal release. Fresh now presents placeholders immediately and fills captures progressively. Cached show timings begin inside the controller and do not establish physical key-to-photon latency; the user's stored Fresh preference is consistent with the audit's 196–315 ms show timings.

## 2026-10-17 — Retained previews (#84 follow-up)

Supersedes the earlier per-session Fresh clearing described above. Both sources now retain successful memory images on reopening. Fresh keeps no disk previews, cancels unfinished captures on hide, and still accepts tilted Stage Manager images. Warm reconciles hidden removals and prioritizes changed focus/title/visibility. Unchanged onscreen windows are eligible after one second for the current window or 30 seconds for others, checked only on existing warm events; no timer. Failures retain old images. Settings and README explain the updated lifetime.

## 2026-10-18 — Additional background themes

Appearance adds Graphite Gray (#292D2B) and Deep Purple Gray (#36313F), both using the dark palette. The two-column preview grid now derives its rows from the theme count; all six themes and lower controls remain accessible through scrolling. Existing stored selections and the default are unchanged.


## 2026-10-20 — Native Chinese search (#103)

The search row now hosts `SearchEditor`, a real `NSTextView`. AppKit owns marked
text, selection, candidate placement, clipboard and per-session undo. Only the
complete committed string updates filtering; window/preview refreshes never write
back into the editor. Cancellation that clears marked text must publish the native
final string, including the empty string. Do not restore a guessed pre-composition
snapshot or let a composition-ending key also execute a panel command.

Card mouse actions capture the actual Window before dismissing composition. Empty
results plus Enter leave editing active. Every dismissal clears editor/undo state;
callbacks capture the panel session to reject old deliveries.

System Pinyin and Rime were exercised through this production panel/editor in an
isolated desktop fixture. That fixture has no global EventTap and uses fake window
identities, so it does not prove global gestures or real window activation. See the
[validation record](../../validation/2026-10-20-chinese-search.md) for evidence and
remaining acceptance before making PR #103 ready.


## 2026-10-26 — Search caret appearance

SearchEditor draws a 2pt rounded caret using the native insertion-point callback.
AppKit still owns blinking and input-method coordinates; redraw invalidation covers
the widened stroke. Panel layout always establishes the editor's 22pt height and
centers the font line with text-container padding. Previously the width-only frame
check could leave a zero-height editor. Theme appearance selects white/black ink;
an accent-color comparison is preview-only, with no new setting.

## 2026-10-26 — PR #103 review follow-up

Removed the stale search-text cache: programmatic resets always refresh the hint,
accessibility value and layout, while SearchEditor still avoids redundant string
writes. Regression coverage types natively, dismisses and reopens the panel.
Controller coverage now observes actual key-panel/editor focus acknowledgment,
forwarded first-key filtering, reserved modified Tab navigation and rejection after
dismissal. Editor key tables cover panel commands and composition-first Enter and
Option-comma. Font/size settings remain deferred until this review work is complete.
