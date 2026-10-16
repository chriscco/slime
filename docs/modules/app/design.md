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

A 720×510 pt AppKit window contains flat General, Appearance, Shortcuts, and About sections. The sidebar uses solid surfaces and borderless navigation. The body scrolls, keeping appearance controls reachable beneath a two-column theme preview grid. Preview buttons draw static opaque schematics, expose native radio-button state, and remain alive when selection changes so keyboard focus is retained. The window moves to the active Space, supports full-screen auxiliary presentation, and explicitly orders itself frontmost. It floats while key and returns to normal level when resigning key so Sparkle dialogs can appear above it. About shows the bundled 3:1 banner with 12 pt clipped corners, the bundle version, repository link, and update controls. Missing artwork falls back to the name. A settings-local Command-W handler calls `performClose`, preserving other windows' shortcuts.

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

## Signed updates (0.0.8)

`AppDelegate` owns one main-actor `AppUpdater` and starts it at launch. The adapter
constructs `SPUUpdater` with `SPUStandardUserDriver` only when bundle metadata contains
an HTTPS feed and a 32-byte Ed25519 public key. Calling `start()` explicitly lets startup
errors become a localized unavailable state in settings. Sparkle owns its schedule,
download validation, installation, and relaunch; none of this runs on the event tap.

Settings yields its floating level when it resigns key status so update dialogs stay visible;
becoming key restores its foreground level. Settings receives the adapter, observes its
check/preference changes, and refreshes the
existing controls in place. Check availability prevents overlapping requests. Automatic
checks opt in through Sparkle's own persisted preference; no duplicate settings key or
timer is maintained. Bundle policy disables automatic downloads/installations and profile
submission. Standard Sparkle UI asks users to download and install/relaunch.

Packaging embeds/signs Sparkle's framework and nested helpers, copies the About banner,
and requires signed feeds plus archive verification before extraction. Local builds can
omit the public key and remain unavailable for updates; tagged release builds fail closed.
The release pipeline signs and verifies the DMG and appcast before publishing them with
the checksum and reviewed notes. See [publishing setup](../../releases/README.md) for key
ownership and [validation](../../releases/0.0.8-updates-validation.md) for tested boundaries.
