# Panel font preferences

Issue #104; separate PR based on #103's native search editor.

## Approved behavior

Appearance settings offer one font family for search and window card titles:
System (default), System Monospace, Hack, Menlo, Monaco and Courier New.
Named fonts use local installations only. Unavailable entries are labeled and disabled;
a saved unavailable font falls back to the system font without overwriting the preference.
AppKit provides missing-glyph fallback, including Chinese and emoji.

Search and title sizes are independent: 12, 14, 15, 16, 18, 20 pt. Defaults remain
15 and 12 respectively. Invalid stored values use defaults. Changes persist and
apply immediately. Settings shows only the font selector and pt size controls, without sample text.
Other labels, group headings and settings typography retain their system fonts.

Search line geometry follows font metrics within the existing 32pt search row.
Card titles remain one line with tail truncation; their area grows upward, reducing
preview height when necessary, without overlapping the selection underline.
Appearance changes must preserve search contents, marked text and selection.
Reused and newly created cards receive the chosen font.

No font downloads, bundled font files, arbitrary font picker or new dependencies.

## Implementation and validation

1. Settings.swift: persist/validate family and independent sizes, resolve native fonts.
   Tests observe fresh defaults, reconstruction, invalid values and available-font resolution.
2. SettingsWindow.swift: existing popup/action pattern, bilingual availability labels,
   pt-only size controls; UI tests operate controls and observe saved values.
3. PanelController/PanelWindow/CardGridView: propagate fonts and derive text heights.
   Tests cover all offered font sizes, cached card reuse and composition preservation.
4. Run scripts/test, build signed release, inspect native rendered previews, update module
   handoff/design and release notes, create separate PR and check current-head CI.
