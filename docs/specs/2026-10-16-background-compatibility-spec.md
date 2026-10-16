# Background materials and experimental macOS 15 support

- Status: Design confirmed in conversation; written spec for review.
- Issue: [#77](https://github.com/chriscco/slime/issues/77).
- Target: 0.0.8. This document does not implement compatibility or claim native validation.

## Goal

Offer a fully opaque panel on every supported system and optional Liquid Glass on
macOS 26 and later. Target macOS 15 as an experimental compatibility tier, with one
shared settings page and panel layout. Keep the existing macOS 26+ experience by default.

## Scope and delivery

Implement this work in a separate PR from preview-source PR #75 and settings/updater
PR #76. Neither feature is a prerequisite for choosing the panel material. Settings
and packaging files overlap, so review their combined result after rebasing. If #76
lands first, update its appcast compatibility checks as part of this implementation;
if it lands later, #76 must adopt the new deployment minimum before merging.

No virtual machine installation, macOS 14 support, Intel/universal distribution,
new capture API, blur fallback, or updater redesign is included. macOS 14 is deferred
because sustained runtime testing is unavailable; API availability alone is insufficient.
This spec and its implementation belong in the same PR, which adds one entry to
`docs/releases/0.0.8.md` and updates the app design, decisions, and handoff documents.

## Appearance and preferences

Use the same Appearance page on both system tiers. Separate **Background material**
from the existing **Background color** preference.

| Control | macOS 26+ | macOS 15 |
|---|---|---|
| Background material | Liquid Glass / Solid | Static Solid label with requirement explanation |
| Background color | Black, white, deep blue, follow system | Same |
| Glass style and strength | Visible only while Liquid Glass is selected | Hidden |
| Accent color and panel corner radius | Always available | Always available |

Provide English and Simplified Chinese strings. The older-system explanation says
that Liquid Glass requires macOS 26 or later; do not present a disabled interactive
selector. Keyboard navigation skips absent controls. Existing color swatches and
light/dark text contrast remain available. Material-dependent explanatory text must
not describe glass strength as affecting a solid background.

Persist an optional material preference (`glass` or `solid`). With no saved preference,
choose Liquid Glass on a capable system and Solid otherwise. An explicit Solid choice
survives restart and OS upgrade. An unavailable saved Glass choice resolves to Solid
without overwriting the preference. An unknown stored value uses the default.
Do not save a default merely because settings were opened.

On macOS 26+, a material change applies immediately, without restarting slime. Preserve
existing glass style/strength, color, and radius preferences when switching materials.
Switching back restores the saved glass values. An older-system user with no explicit
preference gets the capable-system default after an OS upgrade.

## Rendering boundary

Keep one panel content tree for search, cards, selection, and closing animations.
Use the existing NSGlassEffectView only behind a macOS 26 availability boundary;
isolate all declarations exposing its types, including the GlassStyle conversion.
Solid rendering uses an ordinary layer-backed view with alpha 1 for the selected
background color, independent of stored glass strength. Do not retain a glass effect
under the opaque surface or create one on an unsupported OS.

Both materials preserve panel shape, clipping, window shadow, search focus, accessibility,
and the existing Reduce Motion behavior. Changing the material must preserve current
search text, selection identity, and focus; it must not trigger thumbnail capture or
window enumeration. Follow-system color responds to appearance changes in both modes.

## Compatibility and packaging

Audit all API availability while lowering the Swift package deployment target and
packaged LSMinimumSystemVersion to macOS 15. Use a modern SDK that provides the glass
symbols; an old deployment target does not imply an old SDK can build the app.
Runtime availability checks must cover every newer API, not only the initial panel.

Keep the existing bundle identifier, signing identity, architecture, and permission
requirements. Check any minimum-system-version constants, packaging assertions,
README requirements, release metadata, and Sparkle appcast generation/tests against
the same macOS 15 minimum. Preserve dependency minimums where they are independently
correct; do not mechanically replace every occurrence of an OS version.

The README describes macOS 15 support as experimental until the native checklist below
passes. It must not claim full compatibility based on compilation or CI alone. Do not
introduce development-version/latest-DMG banners in either language.

## Verification and acceptance

Automated tests must cover:

- Missing, explicit, and invalid material preferences, including unavailable Glass and
  upgrade behavior; capability resolution is testable on the current development host.
- Correct settings controls for both capability states and both materials, with glass
  parameters preserved across switches and no reset of unrelated preferences.
- Opaque Solid rendering even with glass strength set to 100%, and readable foregrounds
  for all four colors in light and dark appearances.
- Live material changes preserving search and selection without additional captures.
- Matching package, bundle, and updater OS requirements after integration with #76.

Run the full local test command and current-head CI. Add a macOS 15 runtime CI lane for
compatible tests and an application launch smoke check where the runner permits it.
Build with a sufficiently new SDK and execute compatible artifacts on the older runner
if that runner cannot compile the glass APIs. Report skipped desktop checks explicitly;
a runner limitation is not a successful native acceptance result.

On macOS 26+, manually verify switching both ways, themes, clipping, and search focus.
For macOS 15, use an external tester or suitable hosted desktop rather than installing
a VM on the user's machine. Record OS/build and signed artifact identity when checking:

1. Launch and reopen settings; no missing-symbol crash or unresponsive panel.
2. Accessibility denied/granted/restart behavior; native switching remains usable on failure.
3. Screen Recording denied/granted/restart behavior; denied capture retains app-icon cards.
4. Visible and Stage Manager windows: enumerate, capture or explain fallback, activate,
   and request close without closing a different window or dismissing save confirmation.
5. Multiple displays/Spaces, search, Command-W in settings after #76, and panel dismissal.

Until that evidence exists, macOS 15 remains experimental. VM performance, CI timings,
and existing newer-OS measurements must not be presented as macOS 15 performance data.

## Decisions

A shared page with capability-dependent controls avoids two settings implementations.
Opaque solid rendering keeps the fallback small and lets it be exercised on the
current OS. NSVisualEffectView blur would add a third material that was not requested.

A low deployment target is an API compatibility statement, not desktop verification.
macOS 15 is the initial older-system target; GitHub has announced retirement of macOS
14 runners on November 2, 2026, which makes that additional tier harder to maintain.

## References

- [Apple NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [GitHub macOS 14 runner retirement](https://github.com/actions/runner-images/issues/13518)

## Revision log

- 2026-10-16 — Keep this single-scope spec and its implementation together in PR #78.
  Separate spec PRs are reserved for shared designs spanning multiple implementation PRs.
