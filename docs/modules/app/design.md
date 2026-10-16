# App design

`main.swift` sets accessory activation policy before entering the run loop. `AppDelegate` assembles SettingsWindow, the menu-bar item, EventTap, WindowCache, and PanelController on the main actor.

The menu bar is installed first and remains usable while disabled, without Accessibility permission, or after tap startup failure. Enabling checks Accessibility and starts the tap/cache. Failure shows a localized error and turns the switch off. Screen Recording is optional and affects previews only. Permission onboarding requests a restart after authorization.

Disabling immediately dismisses the panel and calls `configure(false)`, releasing keyboard interception while retaining preferences. Enabling again reuses the installed tap. Repeated tap timeouts disable interception, cancel the session, and explain that native Command-Tab is available.

## Wiring

- Tap effects → `panel.handle`; panel dismissal/disable → `tap.cancelSession`.
- `panel.onActivate` → `WindowActivator.activate` and `cache.noteActivated`.
- `panel.onRefresh` → `cache.refresh`; cache publication → icon/thumbnail warming and `panel.setWindows`.
- `panel.onClosed` → `cache.noteClosed`; `onCloseFinished` → revision-checked `tap.completeClose`.
- Panel/menu settings action → `settingsWindow.show`.
- Settings changes refresh panel appearance without changing query, focus, or window identity, rebuild menu labels, and start/stop interception only when enabled state changes. Language persists immediately; the next panel presentation reads it. Application names and window titles are never translated.

## Settings

A 720×510 pt AppKit window contains flat General, Appearance, Shortcuts, and About sections. The sidebar uses solid surfaces and borderless navigation. The body scrolls, keeping appearance controls reachable beneath a two-column theme preview grid. Preview buttons draw static opaque schematics, expose native radio-button state, and remain alive when selection changes so keyboard focus is retained. The floating window moves to the active Space, supports full-screen auxiliary presentation, and explicitly orders itself frontmost. About contains only slime, the bundle version, and the repository link.

Settings accepts isolated UserDefaults for tests. English is the default. Existing glass preferences remain; default panel corner radius is 20 pt. In 0.0.6 the sole existing user's saved accent resets once to sRGB #96D76A; later customization persists. The settings selection and panel share the configured accent.

Login launch uses `SMAppService.mainApp` directly, without a duplicate defaults flag. Read system status when settings becomes key; disable the control during registration changes and distinguish approval required, missing app, and failure. Registration is off by default.

## Verification boundaries

Tests cover preferences, language controls, keyboard enable/disable, and asynchronous close integration. Actual login approval/startup, TCC, global shortcuts, focus, and screen composition require native acceptance. Secure Input falling back to native Command-Tab is expected.

## Panel material and OS compatibility

The deployment minimum is macOS 15; build with a macOS 26+ SDK. macOS 15 remains
experimental pending desktop permission, capture, and window-operation acceptance.
`Settings.panelMaterial` is an optional persisted preference. Missing/unknown values
resolve to Glass on macOS 26+ and Solid on 15; an explicit Solid survives upgrades.
A saved but unavailable Glass preference resolves to Solid without being overwritten.

`PanelWindow` retains a stable root and content tree. Only a guarded macOS 26 branch
constructs NSGlassEffectView; Solid removes that host and uses an opaque content layer.
Changing materials preserves search, selection, focus, color, radius, and glass values.
The shared Appearance page offers the selector on 26+ and a static explanation on 15;
style/strength rows exist only for effective Glass. No capture or enumeration is triggered.
