# System design

## Boundaries

| File | Responsibility |
|---|---|
| WindowEnumerator.swift | CG window candidates, AX metadata/matching, known-window filtering, and cancellable AX requests |
| WindowCache.swift | Snapshot publication, coalesced background refresh, window-level MRU, current-window ordering |
| WindowActivator.swift | Cached-target activation and uniquely identified close actions with confirmation |
| ForegroundObserver.swift | Coalesced foreground-window focus/title notifications and explicit observer lifetime |
| Settings.swift / AppIcons.swift | Preferences/localization and application-icon caching |
| WindowThumbnails.swift | Memory/disk preview cache, background capture/loading, live-identity publication |
| EventTap.swift | Event translation, interception, reducer ownership, timeout recovery |

Rendering/selection belong to UI; startup/permissions belong to App.

## Thread ownership

The main actor owns cache snapshots, panel state, and thumbnail bookkeeping. EventTap state belongs exclusively to its tap run loop. Background queues perform enumeration, AX IPC, screenshot capture, and thumbnail disk I/O.

Tap effects are published FIFO to the main actor. Main-actor cancellation, enable/disable, and close completion are sent through CFRunLoopPerformBlock. Increment deliveryRevision before sending a reset so already-enqueued effects are discarded. Core state is not read synchronously from the main thread. The tap callback does not perform AX, disk I/O, or locking.

AXRequest has a small lock protecting cancellation, never held during IPC. A close shares one monotonic three-second deadline across direct access, revealing the target, retrying, and confirmation. Before each AX request, check cancellation/deadline and set timeout to min(one second, remaining time). A synchronous call already executing cannot be forcibly cancelled.

## Enumeration and known windows

CGWindowList with optionAll/excludeDesktopElements establishes the candidate set. Keep layer-zero, positive-alpha windows owned by regular applications other than slime. Do not filter by dimensions: Stage Manager transforms real windows into small tiles. Enumeration currently also checks intersection with active display bounds, converting coordinate systems correctly; destructive close matching does not exclude an already-selected target solely for being outside those bounds.

Read AX windows/main window once per PID. Prefer onscreen CG candidates and, within equal visibility, candidates with CG titles. Match near-equal frames, preferring equal titles, and allow each AX element to claim only one CG window. Add main windows by element identity rather than merging different elements that share geometry.

Selection evidence includes a current AX counterpart, eligible onscreen evidence, or a valid known entry. An explicit AXUnknown subrole plus empty title vetoes a helper surface before any positive evidence. Unknown subroles do not veto. With readable AX and an explicitly empty CG title, onscreen state alone cannot admit Chromium toolbar hosts. Retain offscreen known entries when title access is unavailable, a nonempty title exists, the entry was verified as standard AX, or it is known minimized. If AX reports at least one standard window, nonempty same-PID CG titles can also recover previously unknown offscreen windows.

A complete empty AX window list plus main-window noValue is stronger evidence than unsupported/timeout/partial reads, but remains Space-dependent. It must not remove siblings explicitly preserved by a known single-window close. Never interpret an unreadable snapshot as an empty application.

Known entries persist as JSON in UserDefaults `cache.knownWindows`, carrying appName, title, minimized state, and optional axVerified/closed/survivedClose flags. App-name mismatches invalidate reused IDs. Optional fields preserve older cache compatibility; rejected/missing entries are pruned naturally without requiring users to clear preferences.

The 0.0.5 authorized native probe reduced Chrome from five cached entries to three real windows and Feishu from two retained surfaces to zero after red-button closure. It used actual enumeration, not app-name/size exceptions. A CLI lacking AX permission was not accepted as evidence of an empty app.

## Refresh and MRU

WindowCache publishes immutable snapshots after checking generation. Refreshes coalesce into one running enumeration and at most one pending refresh. A newer refresh cancels the obsolete AXRequest; the pending refresh starts with current known/MRU state. Cancellation is checked between AX attributes and app groups. Explicit activation/closure invalidates in-flight results.

Snapshot includes every accepted window, with the current window first and the rest in
window-level MRU. Foreground AX focus evidence updates recency even within one application;
app-only fallback does not promote the requested window. Grouping orders apps by their most
recent member. The panel initially highlights the previous window by identity, then freezes
existing card order for that session while applying title changes/removals and appending new
windows. Search keeps relevance ordering.

Observe only the foreground app and its focused window. Coalesce focus/title/create events
before bounded background reads; publishing a snapshot can resolve an unknown identity but
must not initiate another discovery loop. Remove observers on disable and discard obsolete
completions. Native AX references remain in System, never in Core or persisted caches.

## Activation and closing

Ordinary activation immediately unhides/activates the application, then uses the cached
same-PID/window AX target off the main thread to unminimize/raise and confirm focus. It does
not enumerate windows, capture previews, or retry identification. Missing/ambiguous/rejected
targets retain application fallback without an error popup. The request budget is 150 ms;
an already-running system IPC can exceed its requested timeout. Overlapping requests cancel
obsolete work and must not allow a stale completion to update MRU.

Enumeration retains exact AX identities before considering unique frame/title evidence.
An absent retained identity must not be rebound to a same-frame sibling. Fresh AX titles
outrank stale CG names; focused-window title events update card/search text independently
of preview caching. Unobserved offscreen windows may lack an exact native mapping until
visited; application fallback is the accepted degradation.

Close requires the same PID and a one-to-one frame match on both CG and AX sides, or a nonempty live title unique among eligible CG surfaces and standard AX windows. Read the close button, then reread both sides and require the same CG geometry and AX element immediately before AXPress. No cached-title guessing, private ID mapping, quit, or automatic save confirmation.

Activation can transform Stage Manager geometry. Retry an unavailable identification only before a close action was sent and within the shared deadline. If direct access remains unavailable, UI deliberately ends its session and reveals the application. An unsuccessful NSRunningApplication activation can use the public AXFrontmost attribute before re-identifying/raising the target. Actual target matching is still required for closing; no foreground Command-W fallback exists. The user stays in the target application afterward.

AXPress success is not proof of closure. Bounded, progressively spaced checks inspect the selected target for CG disappearance or AX invalidation. A positively identified AX sheet returns confirmationRequired so UI hands control to the app. Avoid repeated full-app snapshots during confirmation; an app-wide empty AX list alone is no longer used to prove a specific close. Budget exhaustion preserves an unconfirmed window.

At close start, UI captures same-app siblings. On confirmed closure, `noteClosed` invalidates stale enumeration, removes only the target, and restores captured siblings if a concurrent refresh omitted them. Persist closed for the target and survivedClose for its siblings. Retained CG surfaces cannot resurrect the closed target while offscreen/unmatched. AX matching removes sibling protection; missing CG IDs prune entries; visible/reopened targets can reuse IDs.

Known limit: a protected sibling later closed outside slime can linger if AX still cannot see it and its CG surface remains. Precise resolution requires per-window lifecycle evidence, not app-wide empty-list inference.

## Thumbnail cache

`warm(allWindows)`, `image(for:)`, and onChange separate caching from AppKit rendering. Memory CGImages, pending/refreshing IDs, negative-cache entries, ownership, and publication tickets are main-actor state. The UI wraps CGImages only when their identity changes.

Load PNG caches and capture screenshots off the main thread. Disk misses are attempted once per live identity. Per-window tickets and owner PID checks reject late results after removal/replacement; loaded images cannot overwrite a newer memory capture. Capture remains serial within each batch, and in-flight IDs are deduplicated. The panel's optional first-frame wait is bounded to 300 ms; loading cannot block its main-thread timer.

Capture uses SCShareableContent once per batch, SCContentFilter(desktopIndependentWindow:), and SCScreenshotManager at 320 px width, preserving aspect ratio. Do not call private SkyLight APIs. Missing Screen Recording permission returns no images and retains normal window switching.

Plan rules:

- Missing images are needed; previously unrenderable offscreen windows are not repeatedly retried.
- A window returning onscreen gets another capture opportunity.
- Cached onscreen windows refresh after actual window-cache updates; refreshes do not block first presentation.
- Cached offscreen windows retain their last good image.

Fallback is fresh image → last good cached image → generic small-window/app-icon drawing. Parked, minimized, and other-Space windows may not be rendered by WindowServer. Serial capture and a six-second retry in earlier diagnostics did not fix those failures; they were not evidence of throttling.

PNGs live at `Application Support/slime/thumbs/<windowID>.png`, historically about 20–40 KB each. Cleanup follows all live windows, not a filtered search result or selection. Disk filenames still use window IDs; persistent cross-boot identity is not guaranteed. Current-window inclusion does not change this cleanup contract.

Reject visibly invalid captures by downsampling to 32×32, checking four corners inset two pixels for opacity, and requiring at least two quantized colors. Ignore SCK single-window shadow framing. Sampling the very outer corners incorrectly rejected real rounded windows; the inset fixed that native finding. Uniform-color real windows can still fall back to an icon.

## Event processing

1. Re-enable a disabled tap immediately unless repeated timeout disables have triggered degradation.
2. Translate flagsChanged and keyDown into Core events.
3. Reduce all enabled, nondegraded states on the tap run loop. Swallow untranslated keyDown only during an open session.
4. Suppress close autorepeat and pair swallowed keyDown with exactly one corresponding keyUp. Cancel/configure clears pairing and invalidates queued effects.

Session tap uses head insertion/default interception. Native acceptance must verify it gets Command-Tab before the system; changing to HID tap is a separate historical fallback, not an assumed fix. Secure Input can withhold events and leave native switching active.

## Interfaces and limitations

`WindowEnumerator.enumerate(known:request:)` returns WindowEnumeration and must run off the main thread. WindowCache exposes start/refresh/snapshot/noteActivated/noteClosed/publication. WindowActivator exposes activate/close/revealForClosing. EventTap exposes start/configure/cancelSession/completeClose.

Within an open session, ordinary Command-letter combinations such as Command-C/Command-Q still become filter characters unless assigned a dedicated shortcut. Outside the session, ordinary keys pass through. AX frame/title matching remains heuristic; unavailable or ambiguous destructive targets are rejected. Applications that report real unnamed windows as AXUnknown can be filtered incorrectly. Public AX coverage varies by Space/application, and never-observed offscreen windows may remain undiscovered, especially without CG titles. Chrome's AXManualAccessibility was unsupported in earlier tests; some Electron apps still exposed no windows after waiting five seconds.

The 0.0.6 performance spec governs deadline, cancellation, rendering, and 10/50/100-window acceptance. Offscreen/unit tests alone cannot certify native activation, Space switching, physical shortcuts, or save-dialog behavior.

## Preview source and session boundaries (0.0.8)

Settings persists `preview.source` as `cached` (default/unknown-value fallback) or `fresh`.
AppDelegate configures the source before cache startup and on settings changes. Cached mode
retains background warming, disk cache, negative cache, and onscreen refresh.

PanelController calls `beginSession` before rendering and `endSession` on every hide path.
Fresh mode clears memory/tickets/attempts at both boundaries, announces the new session so
reused cards clear their previous images, and ignores `warm` while closed. `warm` captures
new identities once, deduplicates repeated snapshots, and allows a failed offscreen identity
one retry when visible. Opening triggers the capture batch and normal window refresh;
search/selection do neither. No explicit refresh command exists independently of opening.

Warm tasks validate tickets again before scheduling any disk read. Read and capture tasks
are tracked together; cancellation propagates into detached disk readers between files.
Capture tasks carry the source selected at request time. Mode/session changes invalidate
tickets and cancel tasks; results must pass ticket validation before publication or save
scheduling. Disk tasks are background/cancellable and serialize writes/pruning through an actor. Already-started file operations may finish;
fresh mode schedules no new disk work and is not a secure-delete feature. The existing 300 ms
presentation deadline is unchanged. Fresh validation permits transparent corners, rejects
transparent/solid samples, and uses the existing proportional image canvas.
