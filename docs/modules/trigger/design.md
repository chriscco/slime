# Trigger design

`reduce(state, event) -> (state, [Effect])` is a pure function. EventTap translates global gestures and exclusively owns panel-command state; PanelController executes UI effects and maintains bounded selection.

| State | Transition |
|---|---|
| idle | Modifier down → armed; otherwise pass through |
| armed(m) | Tab → holding/showPanel; matching modifier up → idle; ordinary shortcuts pass through |
| holding(cmd) | Command up → activate/hide until typing; first character → typing; explicit focus → lingering |
| holding(opt) | Option up → lingering; first character → typing; explicit focus → lingering |
| typing(m) | Keep ordinary-letter compatibility until matching modifier up → lingering; release does not activate |
| lingering | Native editor handles text/composition; panel commands return to this reducer. Enter requests activation, Escape cancels, Command-comma opens settings |
| closing | Modifier changes retain the session; navigation/input/repeated close are swallowed; Escape/settings can end it; closeFinished → lingering |

Command-D from holding or lingering enters closing and emits closeWindow, preventing Command release from activating a neighboring window. UI completion, including failure or an empty list, sends closeFinished on the tap run loop. Revision checks discard obsolete completion deliveries.

`panelStep` shares ordinary navigation, filtering, and finish behavior. Core selection is an unbounded counter; actual counts, grouping, wrapping, and identity-following belong to PanelController/GridLayout. Enter requests activation without ending the state: the controller dismisses only when a real selected row exists. An empty-results Enter keeps the session and editor alive.

Swallow only owned events. Non-Tab keys outside a session pass through. EventTap handles untranslated navigation/closing key-downs and close autorepeat; focused native editing follows the AppKit path described below. Core never imports AppKit, CGEvent, or AX.

The 0.0.6 close deadline and cancellation live outside Core. An intentional handoff to the target application ends the tap session; it must not synthesize a new lingering session after confirmation.


## Native editing boundary (0.1.0)

Committed text arrives as a complete query replacement rather than append/delete
commands. Equal text leaves result selection intact. The UI owns the actual bounded
selection; Core retains only the counter needed for pure state transitions.

Composition, selection, clipboard and per-session undo are AppKit responsibilities.
The native editor sends panel commands to the same tap-owned reducer only outside
composition. Left/right edit text; unmodified up/down and Tab select windows.
No native editor callback may synchronously read or mutate tap-thread state.
Revision-gated delivery rejects input queued before cancellation or disable. Until
the controller confirms a key panel with the editor as first responder, the tap
copies and swallows keyboard events for ordered delivery on the main thread.
Handoff is bounded to 64 pending packets and two seconds; draining an unconfirmed
queue does not restart that deadline.

After focus confirmation and queue drain, ordinary native keys, releases and modifier
changes pass through normally so input sources and Rime can handle their own events.
Command/Option-Tab remains reserved for the open panel and is routed through the
editor, preserving composition priority. Control-Space is allowed through even
during handoff. Buffered key releases follow their intercepted keydowns; modifier
events are never replayed as a second synthetic event. A failed handoff disables
interception and uses the existing degradation notification.
