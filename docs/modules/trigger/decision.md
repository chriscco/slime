# Trigger decisions

Historical entries retain their original order; the final entries supersede earlier behavior.

## 2026-10-12 · Keep arrow-axis geometry in the panel

- **Context:** Up/down moves a row, while Tab/left/right moves one cell. A bare moveSelection delta cannot distinguish them.
- **Decision:** Carry axis and step in Event/Effect; PanelController translates them into layout movement. The initial conversion multiplied vertical steps by column count; row-aware wrapping later refined that behavior.
- **Alternatives rejected:** Passing columns into the reducer, which couples pure state tests to layout, or passing pixel displacement through Core.
- **Cost:** One translation between effect and movement.
- **Revisit:** A third axis appears or the panel needs the original key identity.

## 2026-10-12 · Command-F changes Command holding to lingering

- **Context:** The user could not release Command after focusing search without activating a window.
- **Decision:** `holding(.cmd) + Command-F` becomes lingering, with swallow/focus effects. Enter activates and Escape cancels. Option-F remains unchanged because releasing Option already lingers.
- **Alternatives rejected:** Keeping the literal original spec transition; also changing ordinary typing to linger, which would break the established hold/type/release gesture and require another decision.
- **Cost:** Command mode has two exits. Under the then-current modifier-restart behavior, pressing Command again after Command-F started a fresh gesture; the later 0.0.5 decision supersedes that part.
- **Revisit:** If the two exits are confusing, consider lingering on the first typed character, with explicit approval of the gesture change.

## 2026-10-11 · Pressing a modifier while lingering begins a new gesture

- **Context:** The original state table changed lingering to armed without hiding the existing panel, leaving an orphaned panel after the modifier was released.
- **Decision:** Add hidePanel to `lingering + modifierDown → armed`, treating this as a fresh gesture with an empty query.
- **Alternatives rejected:** Keeping the old query and panel, or delaying dismissal until armed returns to idle, which complicates the no-Tab gesture.
- **Cost:** Any modifier press dismisses a search even when intended for another shortcut.
- **Revisit:** If this becomes annoying, keep the panel and remove the transition. The 2026-10-13 entry does exactly that.

## 2026-10-11 · Pure reducer; pass through unless explicitly swallowed

- **Context:** Incorrect interception can break the system keyboard. Splitting decisions across CGEvent and NSEvent handlers makes exhaustive testing impractical.
- **Decision:** Put decisions in the pure reducer; pass-through is the default.
- **Alternatives rejected:** Untestable translation-layer interception, or swallowing unknown combinations by default.
- **Cost:** Events require translation, new keys need explicit handling, and unspecified state/event combinations need a safe default.
- **Revisit:** A platform behavior cannot be represented by the reducer. Secure Input is outside this boundary: macOS does not deliver those events at all.

## 2026-10-13 · Modifiers preserve a lingering session

The user's Option-Tab → release Option → Command-shortcut failure overturns modifier-restart behavior. Lingering retains query and selection. EventTap owns the whole session; remove the second AppKit reducer path. Cancellation/disable synchronize through the run loop and revisions without locking the tap.

Closing pauses input/navigation while retaining Escape/settings exits, then returns to lingering. Command release cannot activate a neighbor and autorepeat cannot close again. UI session generations and tap revisions separately isolate stale work.
