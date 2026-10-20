# Panel decisions

Historical entries retain their original order and measurements. Later entries explicitly supersede earlier choices; historical dimensions are not current defaults.

## 2026-10-12 · Window thumbnails replace app-icon cards

- **Context:** 0.0.2 excluded screenshots until the Stage Manager spike. The spike found normal captures reliable (SCK 17–100 ms, median about 22 ms), but parked windows needed their last good image.
- **Decision:** Use 160×120 landscape cards (160×100 image, 4 gap, 16 title), reducing five columns to four. Show the full aspect ratio and keep card size unchanged when falling back to icons.
- **Rejected:** A small landscape image inside a 112 pt portrait card, or a second card shape for missing previews.
- **Cost:** Panel width grows from 620 to 700 pt and loses one column.
- **Revisit:** Adjacent windows remain hard to associate with apps; add visual grouping and recalculate layout.

## 2026-10-12 · Glass strength is an overlay, not tintColor

- **Context:** Five regular glass views with black tint alpha 0/0.25/0.5/0.75/1 looked identical over a rainbow background. NSGlassEffectView had no opacity property; tint alpha did not provide density.
- **Decision:** Use PanelContentView's existing layer as a solid overlay above glass and below content, with alpha `1 − strength`. Measured background visibility changed while text stayed sharp.
- **Cost:** Match the content corner radius to the glass to prevent black corners. Fully transparent still includes the glass material's refraction.
- **Revisit:** Apple supplies a real glass density/opacity control.

## 2026-10-12 · Fixed default accent rather than system accent

- **Context:** Candidates included controlAccentColor, selectedContentBackgroundColor (dark 0.788/0.376/0.012, light 0.851/0.420/0.039), and keyboardFocusIndicatorColor at alpha 0.5.
- **Decision:** Fixed orange 0.969/0.510/0.106, customizable through the color picker. Its contrast was checked against near-black with a 2.5 pt line. The owner did not want system-theme coupling or a follow-system preference.
- **Cost:** Replace optional glassTint with nonoptional highlightColor, removing the old white-means-clear convention. System accent choices were limited to the documented preset values.
- **Revisit:** Users want system-accent following. The 0.0.6 entry changes the default color, not this independence.

## 2026-10-12 · Consistent selection/search surfaces and identity-based card reuse

Two decisions followed feedback in issues #34/#35.

**Visual design:** A filled square selection and solid black search field looked intrusive. Use a card-aligned 12 pt rounded outline, 2 pt selection stroke, and 8% matching fill; keep labelColor text. Search becomes an 8 pt rounded pill with 8% white, secondary magnifier/placeholder, and primary query text. Reject an expanded selection border that clips at document edges, changing selected text color, solid controlBackgroundColor, and a real NSSearchField that would introduce a competing field editor. Lower contrast requires native glass acceptance. Revisit if selection/search remains hard to see.

**Reuse:** Each asynchronous refresh previously destroyed/recreated every card, visibly flashing icons. Compare ordered IDs; update matching sequences in place, otherwise reuse surviving instances through an ID pool and add/remove only changed windows. Reject full reconstruction and NSCollectionView complexity for a small manual grid. Subview insertion order no longer equals visual order, so tests inspect identities and frames. Revisit collection/diffable infrastructure if hundreds of windows make this pool measurably expensive.

## 2026-10-12 · Vertical movement wraps by row; Core does not know column count

- **Context:** The thumbnail grid triggered reevaluation of manual layout, retained in the next decision. This entry records navigation semantics.
- **Decision:** Up from the first row wraps to the last, down from the last wraps to the first, preserving column where possible and clamping to a short row's last cell. Horizontal movement is one cell. Core carries axis/step only.
- **Rejected:** Passing columns into the reducer or literally using the spec's flat-index modulo example.
- **Cost:** The illustrative formula in spec §6 differs on incomplete rows; the behavioral row-wrapping requirement in §10 takes precedence.
- **Revisit:** Navigation semantics change, such as explicitly choosing flat-index wrapping.

## 2026-10-12 · Keep manual grid layout and an ordinary highlight subview

- **Context:** The original table decision required reevaluation when adding icons/thumbnails.
- **Decision:** CardGridView/CardView and a highlight in the document view; pure geometry lives in Core/GridLayout tests.
- **Rejected:** NSCollectionView's selection rendering/coordinate overlay requirements and NSTableView's extra table semantics.
- **Cost:** At that point there was no cell reuse; layout and hit-testing were owned locally. A few dozen windows made this acceptable.
- **Revisit:** Hundreds of windows make reconstruction measurably costly. Identity reuse was subsequently added without changing the container.

## 2026-10-11 · Read-only search display and a shared reducer from keyDown

- **Context:** An editable field's field editor consumes Tab, Enter, and arrows needed for window navigation.
- **Decision:** Originally all AppKit lingering keys used PanelWindow.keyDown → KeyTable → reduce; append/delete effects updated the display and query together.
- **Rejected:** Editable fields plus event monitors or special-key interception, requiring two coordinated input paths and introducing focus/IME issues.
- **Cost:** No IME composition or Chinese query entry; ASCII worked. Pinyin was already excluded.
- **Revisit:** Chinese titles become impractical to search through app names/ASCII, also triggering reconsideration of pinyin. Later EventTap ownership supersedes the keyDown route.

## 2026-10-11 · Hide on resignKey

- **Context:** Clicking another app was absent from the keyboard state table and left an orphaned panel.
- **Decision:** resignKey hides the panel and resets phase to idle; panel lifetime requires key status.
- **Rejected:** Requiring an explicit dismissal or installing a global mouse monitor for one case.
- **Cost:** The original tap/UI state could briefly differ; the then-current lingering pass-through and idempotent hide made this tolerable. Later revision synchronization replaces that assumption.
- **Revisit:** A future clickable/persistent panel must survive clicking another window.

## 2026-10-11 · Highlight is a document subview, not NSTableView selection

- **Context:** The spec required a smoothly sliding highlight.
- **Decision:** Manually lay out NSTextField rows and animate the highlight subview's frame.
- **Rejected:** NSTableView selection did not animate as needed and required a coordinate overlay plus reuse/z-order handling; NSStackView offered little for scrolling fixed-height rows.
- **Cost:** No cell reuse; own row geometry and resizing.
- **Revisit:** Icons/thumbnails arrive in 0.0.2.

## 2026-10-13 · Rebalance for 16:10 previews, inset content, wait for first-frame thumbnails

- **Context:** Previews were too small, borders overlapped content, and icons flashed before screenshots.
- **Decision:** Increase 160×120 cards to 240×176 with 240×150 image space; four columns become three, gap 12→16, padding 12→20, yielding 792 pt width. Draw the outline on cell bounds and inset content 7 pt, with tests requiring at least 2 pt clearance. Wait for required thumbnails up to 300 ms; cancelling during the wait shows nothing. Fourteen sampled frames showed no post-presentation pixel change in that test.
- **Rejected:** Expanding the outline outside cells, a fixed unconditional delay, and intentionally flashing an icon before a ready screenshot.
- **Cost:** Cold/new-window presentation can wait 300 ms. Narrower layouts may need fewer columns.
- **Revisit:** Reliable live previews eliminate the need to wait.

## 2026-10-13 · 0.0.5 five columns, underline, and small-window fallback

Implement the merged spec: fixed five columns, 200×160 cards, gap 12, padding 20. Zero to five items keep panel size; narrow screens shrink previews instead of removing columns. Optional app sections use real occupied-row navigation. Earlier evidence favoring 240×176 readability remains relevant: fitting five columns is not proof of recognition quality.

The local visible screens were 1470×867 and 1920×1050 pt, accommodating the 1088 pt proposal. Offscreen rendering checked layout/fallback and pixel tests checked portrait corners; Computer Use timeouts prevented full visual comparison. The size remained subject to native calibration.

Replace the outline with a tint and interruptible underline; initially fade across rows. Draw a generic placeholder window rather than fabricated webpage content. Real/cached previews retain priority. CRT uses a preview snapshot; Reduce Motion fades only.

## 2026-10-13 · Stretching underline and layered CRT

Feedback requested a thicker line and richer CRT. Increase underline thickness from 3 to 4 pt, initially stretching over 240 ms from the current presentation frame, with cross-row fading. Separate picture, beam, and dot over 560 ms: exposure/vertical compression, glowing horizontal collapse, and point afterglow. Only the preview animates. Reduce Motion remains a 120 ms nonflashing fade. Use CALayer, no new resources/dependencies.

## 2026-10-13 · Continuous underline curve and preservation on refresh

Two ease-out segments stopped/restarted at their join; same-item refresh deleted in-flight motion. Replace with a continuous 300 ms sampled curve, retarget from presentation geometry, and preserve motion when selection/target are unchanged. Cap stretch at 52 pt. Native samples rose through about 33/37/42/46/49 pt before returning to 32 pt, including an intervening refresh. Tests cover refresh and rapid retargeting. Cross-row fade and Reduce Motion were unchanged at this point.

## 2026-10-13 · Cross-row line-to-dot flight and flat settings

The user requested cross-row/wrap motion instead of fading. A 400 ms smoothstep move contracted to a 4 pt point in the first 30%, stayed a point in transit, then expanded in the final 30%, retargeting from presentation geometry. Samples were about 28/20/11/5/4…5/12/21/30/32 pt. Reduce Motion placed directly.

Settings adopted a solid sidebar, padding, faint selection, borderless navigation, and no decorative copy. About contains name/version/link only. Unlike the nonactivating switcher, settings uses a floating level and current-Space front ordering.

## 2026-10-13 · Faster elastic cross-row landing

The user found 400 ms too slow. Shorten to 240 ms, stretch initially to 44 pt, shrink to 4 pt, expand to 38 pt at landing, and settle to 32 pt. Bound a single overshoot to 6 pt, including long wraps. If retargeting before reaching the destination row, continue two-dimensional travel instead of jumping y.

Native samples were roughly 38/44/37/20/7/4…33/38/36/34/32 pt with about 4 pt overshoot; same-item refresh preserved motion. Reduce Motion stayed immediate.

## 2026-10-13 · Point phase must cover the main displacement

The user still saw a flying line. Earlier verification checked that width reached 4 pt but missed that fast ease-out completed most movement before contraction. Retain 240 ms, allocating 54/120/66 ms to stretch/contract, travel, and expansion/overshoot. Travel keeps a 4×4 pt point throughout. Tests jointly check width/position for both directions, cross-column moves, and wrapping. Native samples at y≈162/183/214/249/284/311/326 pt all had 4 pt width before landing expansion.

## 2026-10-13 · Remove cross-row flight

The user rejected the overall flight. Delete the branch and its unused curves/options. Cross-row moves and wraps clear in-flight animations and directly place a 32×4 pt line. Preserve same-row 300 ms motion. Replace flight tests with destination/no-animation assertions.

## 2026-10-13 · 0.0.6 close decoration, resizing, and visible search focus

Fade title/tint/underline at close start, leaving only the preview for CRT. Restore direct failures, animate successful height changes over 200 ms, and keep cross-row selection immediate. Use the existing tap-owned filter with an accent focus border and a 90 ms end caret, not a second field editor. Skip unchanged image/grid work and avoid per-frame enumeration or reconstruction. The sole existing user's accent migrates once from any saved value to slime green. The release spec requires native and performance verification rather than assuming animation duration proves smoothness.

## 2026-10-14 · Immediate caret, stronger focus, slightly faster CRT

Owner feedback removes end-caret travel; the previous 90 ms animation is superseded. Keep ordinary blinking, strengthen the focus border from 1 to 2 pt and accent opacity from 65% to 85%. Reduce CRT duration from 560 to 500 ms while retaining phase proportions and the 120 ms Reduce Motion fade. Removing travel avoids its per-edit animation allocation/compositing, without claiming it was a measured bottleneck.

## 2026-10-15 · 0.0.7 theme presets and branded search

Keep black as the default and let System opt into inherited AppKit appearance. Refresh cached CGColors from effective-appearance callbacks rather than polling, and retain the existing glass mask formula. White uses Aqua so text and fallback previews remain readable. The square bundled icon sits outside the field; a passive ⌘F keycap disappears during focus or close status. No new query semantics or caret movement animation are introduced.

## 0.0.7 owner feedback · Readable aligned header

Round the existing logo through view clipping, share the card image inset for header
alignment, and remove the shortcut hint's separate fill. Both placeholder and query
use semantic primary text so dark themes are readable without breaking white mode.

## 2026-10-17 — Reuse detached search cards within a session

Searching to zero results previously destroyed every card, then deleting the query recreated them. Keep detached views for accepted live identities until dismissal instead of introducing collection-view virtualization. This retains at most the session's live-window views and improves repeated searches at the cost of bounded session memory. Revisit virtualization only if measured large-window workloads still need it.

## 2026-10-17 — Present placeholders before capturing previews (#84)

The user approved replacing the complete-first-frame wait with immediate default window illustrations and app icons, followed by progressive real previews. This supersedes the October 13 thumbnail presentation deadline. New images may visibly appear after opening, but keyboard navigation, titles, card layout and selection do not wait for them. Keep the existing serial screenshot path; concurrency experiments are separate.

## 2026-10-17 — Preserve previews across openings

User testing found that immediate presentation exposed Fresh's full placeholder-to-image rebuild on every open. Retain successful memory previews in both modes and refresh only changed identities plus bounded onscreen fallback attempts. Fresh's distinction is tilted-image acceptance and no disk persistence, not per-open memory erasure. Cancel its unfinished captures on dismissal while retaining completed images. Tradeoff: unchanged background contents can remain stale until a later warm event meets the 30-second interval; current-window attempts use one second. No new polling timer or capture concurrency.


## 2026-10-20 — Native Chinese editing and explicit navigation boundaries (#102)

The owner confirmed the 0.1.0 spec in two grilling rounds. Replace the read-only
query and fake caret with native text editing; this supersedes the earlier choice
to exclude a field editor. Committed complete strings drive filtering; marked text
and candidate interaction remain the input method's responsibility. AppKit's
[NSTextView](https://developer.apple.com/documentation/appkit/nstextview) provides
selection, marked text and editing; its
[input context](https://developer.apple.com/documentation/appkit/nstextinputcontext/handleevent(_:))
interprets native input events. Do not implement a pinyin engine or candidate UI.

The cost is an explicit keyboard distinction: focused search owns left/right,
while Tab and up/down select windows outside composition. Composition consumes
its confirming/cancelling key without also executing a panel command. Empty-result
Enter preserves the query; card clicks capture and activate that card's identity,
discarding composition. Undo/redo belongs only to the current search session.

Native cancellation and partial commits follow the input method instead of a
hard-coded “one Escape restores everything” rule. Built-in Pinyin and the owner's
Rime installation are required desktop acceptance targets. Revisit the routing
only if native IME tests demonstrate an incompatibility; simulated marked-text
tests do not establish that the candidate UI works on a real desktop.
