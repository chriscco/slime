# Trigger design

`reduce(state, event) -> (state, [Effect])` is a pure function. EventTap translates events and exclusively owns state; PanelController executes UI effects and maintains bounded selection.

| State | Transition |
|---|---|
| idle | Modifier down → armed; otherwise pass through |
| armed(m) | Tab → holding/showPanel; matching modifier up → idle; ordinary shortcuts pass through |
| holding(cmd) | Command up → activate/hide; Command-F → lingering |
| holding(opt) | Option up → lingering |
| lingering | Modifier changes retain query/selection; Tab/arrows/type continue; Enter activates, Escape cancels, Command-comma opens settings |
| closing | Modifier changes retain the session; navigation/input/repeated close are swallowed; Escape/settings can end it; closeFinished → lingering |

Command-D from holding or lingering enters closing and emits closeWindow, preventing Command release from activating a neighboring window. UI completion, including failure or an empty list, sends closeFinished on the tap run loop. Revision checks discard obsolete completion deliveries.

`panelStep` shares ordinary navigation, filtering, and finish behavior. Core selection is an unbounded counter; actual counts, grouping, wrapping, and identity-following belong to PanelController/GridLayout. Activating an empty list is a UI no-op.

Swallow only when an effect explicitly says so. Non-Tab keys outside a session pass through. EventTap handles untranslated in-session key-downs and close autorepeat. Core never imports AppKit, CGEvent, or AX.

The 0.0.6 close deadline and cancellation live outside Core. An intentional handoff to the target application ends the tap session; it must not synthesize a new lingering session after confirmation.
