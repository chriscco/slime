# System decisions

Historical entries retain their original order and evidence. Later entries explicitly supersede earlier rules.

## 2026-10-12 · Public ScreenCaptureKit instead of private SkyLight

- **Context:** The spec §4 spike found private CGSHWCaptureWindowList about 10 ms faster and able to capture some Chrome windows that SCK rejected with -3811.
- **Decision:** SCShareableContent, a desktop-independent SCContentFilter, and SCScreenshotManager. Parked windows use their last good image or icon because three capture approaches produced distorted, white, or unstable results.
- **Rejected:** Undocumented dlopen-based SkyLight, whose OS-update risk was not worth the small gain; SLSCaptureWindowsContentsToRectWithOptions had a symbol but no public signature, making guessed calls a WindowServer risk.
- **Cost:** Screen Recording TCC and another permission-failure surface; no live parked-window image.
- **Revisit:** Normal-window capture becomes routinely unreliable, or Apple exposes an untransformed composited-window API. Private APIs would require a separate scope decision.

## 2026-10-12 · Disable shadow framing and inset corner sampling

- **Context:** Sampling outer corners rejected every real rounded window: alpha at (0,0) was zero after downsampling 320 px captures to 32×32. SCK shadow framing further inset the actual window.
- **Decision:** ignoreShadowsSingleWindow and sample corners two pixels inward, where native samples reached alpha 255. Distorted tiles still had empty corners outside their x≈10…22 span.
- **Cost:** A narrower opacity check; uniformly colored real windows still fail the color-diversity check and show icons.
- **Revisit:** A measured bad image passes the inset test; narrow or relocate samples.

## 2026-10-12 · Reject stale thumbnails by live identity, not batch generation

- **Context:** Results must not resurrect vanished windows.
- **Decision:** Initially accept results only for IDs in the current live set. A global batch generation creates a hole: B skips IDs pending in A, then A is discarded for being old and nobody captures them.
- **Cost:** WindowServer ID reuse can confuse identity across snapshot boundaries.
- **Revisit:** A closed window's image reappears. The 0.0.6 entry adds per-window tickets/owner checks without invalidating unrelated batches.

## 2026-10-12 · Expose WindowCache.sort internally for regression tests

- **Context:** A four-line sorting defect interleaved one app's windows on cold start.
- **Decision:** Change private nonisolated sort to internal and exercise it with @testable import.
- **Rejected:** Moving four lines into a new Core file conflicted with the small-file-count rule.
- **Cost:** Deliberately depart from the original claim that only Core can be unit tested; the function itself remains pure despite living in System.
- **Revisit:** Three or more such exposed seams justify revisiting the module boundary.

## 2026-10-12 · Veto AXUnknown/empty-title helpers and off-display surfaces

- **Context:** Chrome had three real windows but seven entries. Native diagnostics found AXUnknown, empty-title menu/toolbar surfaces, including 1920×41/47 at x=-1920, that were onscreen and matched AX, so all prior positive evidence admitted them. Real sampled Chrome, ZCode, VS Code, WeCom, and line puppy windows were AXStandardWindow.
- **Decision:** Carry subrole, veto AXUnknown plus empty title before all positive evidence, and never persist those entries. Also reject enumeration frames intersecting no display, using testable display geometry.
- **Rejected:** Existing positive evidence, retaining rejected helpers in known, size heuristics forbidden by Stage Manager, and vetoing unknown/unreadable subroles.
- **Cost:** A real unnamed AXUnknown window would be lost; display hot-plug can temporarily omit a window. The original assumption that all genuine offscreen frames intersect a display is not a general guarantee.
- **Revisit:** A real window is lost; narrow the veto or investigate another identity signal. Private AX ID mapping was listed historically as a possible separately scoped investigation, not permission to add it.

## 2026-10-12 · Remember previously observed windows across Spaces

- **Context:** After helper filtering, Warp/VS Code each showed only one of two windows. The observed AX window list covered the current Space, while public main/focused-window access exposed only a subset.
- **Decision:** Keep a known table of windows previously visible or AX-matched, retaining last title/minimized state while offscreen and pruning missing IDs each enumeration.
- **Rejected:** Visible/AX-only selection, private APIs excluded by the spec, and size heuristics that cannot separate real-sized ghost surfaces.
- **Cost:** Never-visited offscreen windows may be absent at startup, titles can become stale, and ID reuse can briefly confuse identity.
- **Revisit:** Unvisited-Space omission becomes intolerable; private APIs would explicitly overturn the non-goal and need a separate issue.

## 2026-10-12 · Regular apps plus visible/AX evidence, without size filtering

- **Context:** A slime-process probe found 252 layer-zero positive-alpha candidates, including per-display menu bars (1470×33 and 1920×30), shared-frame 500×500 surfaces, 1×1/64×64 surfaces, and helpers.
- **Decision:** Keep regular applications and visible or AX windows/main-window counterparts. Each AX window claims at most one CG surface, preferring onscreen candidates.
- **Rejected:** Size filtering; CG names as a mandatory signal because the key disappears without Screen Recording; AXManualAccessibility (unsupported for Chrome and no Electron windows after five seconds); private SkyLight/SLS.
- **Cost:** Incomplete other-Space coverage; at this stage some equal-frame real windows could collapse. Original three-Chrome-window acceptance required those windows to be onscreen or main windows.
- **Revisit:** Cross-Space gaps become unacceptable; reconsider the explicitly excluded private route separately.

## 2026-10-11 · Public frame/title AX matching instead of private ID mapping

- **Context:** CG exposes window IDs while AX exposes element arrays; there is no public direct mapping in the chosen API surface.
- **Decision:** Match frame within ±2 pt, then title when Stage Manager changes geometry. Activation without a match falls back to activating the application.
- **Rejected:** Private _AXUIElementGetWindow because its maintenance risk belongs to the same excluded private-API category.
- **Cost:** Same-title/same-position windows may match incorrectly; parked titles may be unavailable. The original 2 pt tolerance was not rigorously calibrated. Activation's app fallback does not establish destructive-close safety.
- **Revisit:** A reported wrong-window activation requires another identity anchor or a separately approved private-API evaluation.

## 2026-10-11 · Session-level head-insert default event tap

- **Context:** The spec left session versus HID placement to native verification.
- **Decision:** Start with kCGSessionEventTap/headInsert/defaultTap; swallow only explicit effects.
- **Rejected:** Starting at HID without evidence session placement is insufficient; earlier interception may interact differently with Secure Input or OS updates.
- **Cost:** If native Command-Tab wins, the placement must change after verification.
- **Revisit:** Physical-key testing shows the panel never receives Command-Tab; evaluate HID as the spec anticipated.

## 2026-10-11 · Cached snapshots with background refresh

- **Context:** Synchronous AX enumeration on every gesture introduced about 50 ms first-use latency in the original measurements. Incremental AXObserver caching required more code and difficult notification ordering/loss handling.
- **Decision:** Enumerate on startup, render the snapshot immediately on invocation, then refresh asynchronously and discard stale generations.
- **Rejected:** Enumerating only when pressed; implementing AXObserver incrementally before understanding notification reliability.
- **Cost:** Briefly stale initial lists. At this historical point current-window exclusion could also be stale after an external app switch.
- **Revisit:** Refresh freshness is visibly inadequate. Current-window inclusion and coalescing later refine this design.

## 2026-10-13 · Persist known windows with appName as an ID-reuse check

- **Context:** Restarting slime left only the currently visible ZCode window because inaccessible Electron windows depended on the lost in-memory known table.
- **Decision:** JSON in UserDefaults cache.knownWindows; appName mismatches invalidate an old ID. Cover this through knownEntryWithADifferentAppNameIsIgnored.
- **Rejected:** No persistence or storing only IDs, which increases cross-boot confusion.
- **Cost:** The first run still needs discovery across Spaces; old IDs are pruned as observations change.
- **Revisit:** A closed window's row/image reappears.

## 2026-10-13 · Disk previews, negative cache, and onscreen refresh

- **Context:** Most cards showed icons. A ten-window authorized probe captured four; failures were offscreen Warp/Chrome windows. Serial capture and a six-second retry did not change the failed set. A terminal test had 75 successful calls out of 79, but many images were empty/distorted: API success did not imply a usable preview.
- **Decision:** Persist the last good PNG off the main thread; suppress repeated capture of failed offscreen windows; retry when onscreen and refresh visible cached windows on enumeration without blocking first presentation. Add Window.isOnscreen for capture policy, not as an exclusive enumeration filter.
- **Rejected:** Treating serialization as the fix, endless offscreen retries, memory-only caching, and concurrent streams without measured benefit. Serial capture remained because it was stable and sufficient.
- **Cost:** Roughly four PNG rewrites/about 100 KB per typical app switch, stale parked images, and an Application Support cache directory. A shortcut records dirty-write detection as a possible later optimization.
- **Revisit:** Closed images reappear or a public API captures unrendered windows reliably, allowing disk/negative-cache removal.

## 2026-10-13 · Cache cleanup follows live windows, not displayed results

- **Context:** A hidden TextEdit window's seeded magenta cache disappeared after restart. Thumbnail warming received the then-current snapshot excluding the active window, deleting exactly the image needed after switching away. CG's first entry could also be hidden and was incorrectly called current.
- **Decision:** Warm cache.allWindows, not the filtered snapshot; initially identify current as the first onscreen window.
- **Rejected:** A second independent live-window table or a special exemption for the active window.
- **Cost:** Current-window images also refresh, intentionally; warm's input means live rather than displayed windows.
- **Revisit:** Closed images remain visible. Later frontmost-PID checking fixes the multi-display current-window assumption.

## 2026-10-13 · Conservative one-to-one geometry for closing

Activation may fall back to an app; closing cannot guess. Initially require same PID and unique geometry on both CG and AX sides, rechecking before press, with no title fallback. Ambiguous Stage Manager/overlapping targets were rejected with an explanation.

Initially poll CG disappearance for about two seconds after AXPress, preserving the card on timeout and leaving save dialogs to the user. Each AX object retained a one-second timeout. Confirmed deletion invalidates cached enumeration; ordinary activation stays unchanged. Later entries refine title matching, confirmation evidence, and total deadlines.

## 2026-10-13 · Known cache cannot override current no-window evidence

Two-display feedback showed Chrome three windows as five and closed Feishu as two. CG/persisted data identified empty-title toolbar hosts and retained equal-frame Feishu surfaces. The authorized app saw empty AX windows and main noValue; an untrusted CLI's empty result could not establish closure.

Only complete empty windows plus main noValue vetoed an app; errors/unknown did not. Explicitly empty CG titles no longer gained admission solely through onscreen status or unverified cache. Standard-AX-verified unnamed/minimized windows remained eligible; absent CG titles retained the no-Screen-Recording fallback. New fields were optional, with no hardcoded app/size exceptions.

Native enumeration returned Chrome three/Feishu zero, and captured-shape regression tests changed seven entries to three. Without Screen Recording, unverified helpers may still be conservatively retained. Later sibling protection narrows the app-wide veto.

## 2026-10-13 · Limit current-window exclusion to the frontmost app; identify Stage Manager closes

The authorized probe found a Chrome incognito CG entry first while Warp was frontmost. All required windows were enumerated but wrongly excluded. Use the current frontmost PID and clear another app's exclusion immediately on activation.

ChatGPT's full AX frame differed from its transformed CG tile. Permit a same-PID nonempty live title unique among valid CG surfaces and standard AX windows, rereading and validating the same element before press. Ambiguity still rejects; no private API or activation side effect was added at that stage.

A disposable native window reproduced this geometry difference and closed while its process and CG surface remained. Confirmation therefore accepted AX invalidation or offscreen CG plus explicit no-window AX evidence as well as CG disappearance. Never auto-answer save prompts or close working documents for tests. The 0.0.6 decision removes app-wide emptiness as individual close proof.

## 2026-10-13 · Include current windows; retain explicit closed/sibling markers

The owner chose to include the current window at the end. Chrome's omitted windows remained in CG but lacked cache/AX coverage, so a standard-window AX app may recover other windows through nonempty CG titles.

Closing the fourth of four native fixture windows left three live CG windows but empty AX/main noValue; the old veto returned zero survivors. SCWindow.isActive also marked real offscreen windows false, so it was rejected as a liveness test. Persist target closed and sibling survivedClose markers instead; retesting returned three survivors and a running process. Optional fields reuse the storage format, AX rediscovery clears protection, and missing CG prunes entries. Reappearing targets can reuse IDs.

Cost: externally closed protected siblings may linger if AX remains unavailable and CG retains a surface. Upgrade to per-window lifecycle evidence if needed; do not restore app-wide empty-list inference.

## 2026-10-13 · Bounded close transactions, coalesced refresh, and asynchronous disk reads

The 0.0.6 performance review found that per-call AX timeouts did not bound a full close, stale-generation rejection did not stop queued work, and disk cache reads still ran on the main actor. Add a shared three-second monotonic AXRequest with per-call remaining-time checks and cancellation; keep one close transaction through application handoff. Retry identity acquisition only before AXPress. Detect save sheets positively and stop guessing closure from an app-wide empty list.

Coalesce enumeration to one running/one pending refresh and check cancellation between IPC calls. Load thumbnail PNGs off the main thread, remember misses for the current lifetime, and use per-window publication tickets/owner checks so a late disk result cannot overwrite a fresh capture or revive a removed identity. No general scheduler, observer framework, or dependencies are introduced. Native and release-build performance measurements remain required.

## 2026-10-16 · Fresh previews are session snapshots, not video

Keep cached previews as the default. A `preview.source` preference selects fresh captures,
which skip disk loading, saving, and pruning, and discard images/attempts on session end.
A window is attempted once per session, with one additional opportunity when a previously
failed offscreen window becomes visible. Search and selection never request captures.
ScreenCaptureKit remains the only capture API; no activation or Space switching is used.

Fresh validation accepts transparent corners while requiring at least two quantized colors
among opaque samples. This retains perspective renders without stretching them; blank or
unavailable results keep the icon fallback. The existing aspect-fit card renderer suffices.
A read-only macOS 27.0 (26A428) probe produced a recognizable tilted two-pane application image that
cached validation rejects and fresh validation accepts. This proves useful output exists,
not that every minimized or other-Space window is capturable.

Move persistence out of capture and behind main-actor identity-ticket acceptance. Mode
changes cancel capture and pending disk tasks; fresh session boundaries also cancel capture.
A small disk actor serializes writes/pruning so moving saves after capture cannot overlap PNG writes.
Task cancellation is checked before background file work and between screenshots/files.
A file operation already started may finish after the change; preventing that would require
waiting on disk or transactional storage with no benefit to this non-erasure preference.
No lock or disk barrier is added to the input/main-thread path. Existing files remain dormant
in fresh mode. Revisit only if users request a separately specified cache-erasure control.

## 2026-10-16 · Cached native targets and event-driven window recency

Two Warp cards activated the same recent window, and Chrome titles remained stale after
changing tabs. Native diagnostics found incomplete AX window lists, identical Chrome CG
frames, and CG names differing from current AX titles. A first frame/title match is not a
reliable identity. Retain confirmed AX targets while the CG ID/PID remains live, observe
foreground focus/title events, and prefer fresh AX text. No private window-ID API is added.

The owner chose immediate application fallback over an error when exact targeting is not
available, and explicitly rejected extra switching-path enumeration/retries. Activate the
app immediately and bound cached-target operations off the main thread. Only actual focus
can promote a window; app activation alone cannot prove the requested window was selected.

Current window now appears first, followed by window MRU; initial selection remains the
previous window. Grouping preserves member recency, while an open panel freezes existing
card order to avoid moving the user's target. Events are coalesced, without periodic polling.
Revisit only if native acceptance shows public AX coverage insufficient for common apps.

## 2026-10-17 — Do not recapture every window for a title notification

Title-only updates use the list callback without the full preview callback. Real focus changes and enumeration retain preview warming; title changes alone no longer promise a new screenshot. This bounds terminal/browser title activity without adding a timer or dropping Stage Manager background caching. Revisit with targeted, measured content refresh if users need fresher active-window images. Fresh capture and the first-frame wait remain unchanged.

## 2026-10-17 — Stream completed previews and repair late-save pruning (#84)

Publish each serially completed valid screenshot using the batch's existing ownership tickets. A failed or slow window no longer delays already available images or panel presentation. The earlier decision to keep the first-frame wait is superseded by user approval; Fresh still uses no old or disk images. Invalidate the prune memo after a save finishes with no-longer-live IDs, since detached disk submissions need not reach the serial queue in scheduling order.

## 2026-10-17 — Preserve previews across openings

User testing found that immediate presentation exposed Fresh's full placeholder-to-image rebuild on every open. Retain successful memory previews in both modes and refresh only changed identities plus bounded onscreen fallback attempts. Fresh's distinction is tilted-image acceptance and no disk persistence, not per-open memory erasure. Cancel its unfinished captures on dismissal while retaining completed images. Tradeoff: unchanged background contents can remain stale until a later warm event meets the 30-second interval; current-window attempts use one second. No new polling timer or capture concurrency.

## 2026-10-18 — Historical AX association is not permanent duplicate confirmation

A recurring ChatGPT extra card carried `axVerified=true` without an onscreen observation; native enumeration repeatedly returned it alongside the real window even though only the latter had a current AX target. Keep current AX matches, visited windows and minimized windows, but stop using historical AX association alone to exempt unseen same-title offscreen records. This reuses the accepted admission tradeoff: genuine unseen same-title windows may require a visible visit if AX no longer exposes them. Do not infer identity from screenshot darkness, dimensions or app names.

## 2026-10-18 — One recovery within the existing activation budget

The owner approved a single target-app refresh after cached activation fails or has no target. Keep immediate application activation and the successful cached path; recovery shares the original 150 ms budget and all cancellation/generation/focus guards. Do not increase the budget or add waiting/menu automation. A retained identity cannot be rebound to a same-title sibling. This intentionally leaves some Chrome windows unreachable when AX continues to omit them; track the accepted limitation in [#98](https://github.com/chriscco/slime/issues/98). Window-menu automation was considered and rejected for latency.
