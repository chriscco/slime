# Panel design

## Boundaries

`PanelWindow` is a nonactivating floating panel. `PanelController` owns query, window identities, bounded selection, and session generation. EventTap alone drives keyboard state; the panel has no second reducer. System owns enumeration and Accessibility.

## Layout and rendering

- GridLayout has five fixed columns, 200×160 pt cards, 12 pt gaps, 20 pt padding, and a 52 pt search region. Ungrouped lists of zero to five items use 1088×252 pt. More than three rows scroll. A narrow screen reduces preview size while retaining title font size and five columns; panel bounds stay within the visible screen minus 40 pt.
- On opening, app grouping follows first appearance in window MRU and preserves recency within each app. Initial selection follows the previous window ID. Existing card order stays stable for the session; new windows append, and search ranks by relevance. These updates may create another contiguous section for an app. Each group starts a new row with a 28 pt icon/name header. `rowStarts` describes occupied rows; arrow navigation never selects blank slots or headings.
- PanelContentView contains search, close status, scrollable grid, and empty state. The scroll view supplies document width. Render after settling initial geometry; post-close height changes use a 200 ms centered transition, disabled by Reduce Motion.
- CardGridView reuses cards by windowID. Selection is a 13% accent tint with 14 pt corners and a 32×4 pt underline. Within a row, a 300 ms sampled position/width curve begins at the presentation frame, stretches no wider than 52 pt, then settles to 32 pt. Refreshing the same selection does not interrupt it. Cross-row movement and wrapping place the underline immediately. Tint fades independently over 160 ms; Reduce Motion removes travel.
- WindowPreviewView clips the aspect-fit image itself to 10 pt corners, including portrait previews. Real/cached images take precedence. Otherwise draw a generic small window and app icon, without inventing website content. Preserve real titles and expose unavailable-preview help to accessibility.
- Background selection is persisted as Black (default), White, Deep Blue (#0A2C37), or System. Fixed colors force their matching Aqua/Dark Aqua appearance; System inherits application appearance. PanelContentView forwards effective-appearance changes to refresh the base mask and resolves cached search CGColors in its own appearance. Default glass strength is 13%; saved custom values are preserved. The mask retains alpha = 1 − glass strength; full transparency removes the base color. Settings follows system appearance. Default panel corners are 20 pt. The 0.0.6 default accent is sRGB #96D76A, with one-time migration and later customization.

## Session and close lifecycle

Show/hide advances session generation. Thumbnail warm-up waits at most 300 ms; stale callbacks cannot reopen a dismissed or replacement session. Dismissal/disable cancels the tap session.

Command-D captures target and neighbor identities. AX work and CRT run concurrently. At close start, title, tint, and underline fade away; only the card-sized preview snapshot animates. The 500 ms CRT separates picture compression/exposure, a 2 pt luminous beam, and a 4 pt fading point so glow is not flattened into a rectangle. Reduce Motion uses a 120 ms fade.

During closing, cache snapshots can arrive but cannot reorder visible cards. Confirmed closure removes only the target and selects the next surviving neighbor, or the previous one at the end. A direct failure restores the preview/decorations and shows a reason. A fallback that must reveal the target application dismisses slime permanently for that transaction, leaving save confirmation to the user.

One AXRequest supplies a shared three-second deadline and cancellation checks. A replacement session, Escape, settings, or disable cancels pending retries. Deliberate application handoff preserves that request but not the panel session. An outstanding operation prevents a second close from starting. Old confirmed results may update cache, never a new session's UI or tap state.

## Search and performance

The filter is a tap-owned append/backspace query, not an AppKit field editor. A 32 pt bundled slime icon with 10 pt rounded corners sits outside search with a 10 pt gap. The header aligns to the preview images, using their shared inset. Placeholder and query use semantic primary text; the shortcut hint has no independent background. Unfocused search shows a passive ⌘F text hint, suppressed by focus or a close status message. Explicit focus shows a 2 pt accent border with a neutral contrast edge and blinking end caret. Query clipping reserves trailing space for the hint/status. Caret position updates immediately without travel animation; hidden panels stop blinking. Typing from Command-holding enters a persistent search session. Long text is clipped with its end visible. Arrows still select windows; no IME, arbitrary text selection, or mouse window selection is implemented.

Unchanged ordered results skip grid rendering. Cards avoid wrapping an unchanged CGImage again or invalidating its preview. Focus does not restart its animations on every character. Resize frames update geometry without repeating ranking or capture. Thumbnail updates are snapshots, not live video.

## Interfaces and verification

`handle(state:effects:)`, `setWindows`, and `dismiss` connect to activation, refresh, settings, cache closure, tap completion, and cancellation callbacks. Injected close/reveal operations test restoration, cancellation, and session isolation. Layout tests cover geometry, navigation, identity reuse, portrait rounding, and underline behavior.

Offscreen rendering does not certify glass composition, system focus, physical keyboard behavior, or perceived smoothness. The 0.0.6 spec defines native acceptance and the release performance matrix. Historical native-window/underline checks from 0.0.5 remain evidence for that version, not proof that every new path is validated.

Appearance includes a localized Preview source popup: Cached previews (recommended) / Fresh
captures. Its explanation states that fresh captures skip stored previews and some windows
remain unavailable. The controller starts/ends fresh image lifetime with its own session,
clears old card images on reopening, and keeps the existing 300 ms presentation timer.
Image updates do not re-rank rows or request new capture; perspective margins remain transparent
inside the existing aspect-fit preview. A source change resets images and warms the active
snapshot through AppDelegate; a closed panel does not start fresh capture.
