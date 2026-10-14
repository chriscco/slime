# App handoff

Updated 2026-10-14. Branch: `feat/0.0.6`, based on merged 0.0.5 (`fe3a221`). Implementation: [#51](https://github.com/chriscco/slime/issues/51). Final native acceptance and post-merge publication: [#52](https://github.com/chriscco/slime/issues/52). The owner merges; the agent must not merge or tag the feature branch.

## Implemented

Version 0.0.6 (6), supplied application icon, exact sRGB slime-green default and one-time reset of old accents. Subsequent customization persists and updates selected settings controls. Bilingual READMEs include DMG installation and directory trees. All existing module design/decision/handoff documents are in English; historical decisions remain in chronological order.

Command-D has a shared three-second deadline, cancellation between AX calls, and at most one active transaction. It revalidates the CG/AX identity before pressing the close button. Inaccessible targets can be activated/unhidden/raised with public APIs and retried within the same budget. Save sheets are a handoff, never consent. The panel stays dismissed after handing control to the app. An intentional hide's resign-key notification no longer cancels that handoff; user dismissal and replacement sessions still cancel it.

CRT hides selected tint, title and underline; direct failure restores them. Confirmed removals animate panel height for 200 ms. Search has a 2 pt focus border and an end caret that updates immediately. Typing after Command-Tab enters lingering without requiring Command-F; Command release then leaves the panel open. CRT is slightly faster at 500 ms. Cross-row underline placement remains immediate. Reduce Motion keeps the existing fade and disables geometry travel. Cards/images are reused when unchanged.

Enumeration now allows one running and one pending request and stops obsolete AX work. Thumbnail disk reads and eager decoding run in the background; live identity tickets guard publication, misses are remembered, and the existing 300 ms presentation deadline remains.

## Verification and limits

See [release validation](../../releases/0.0.6-validation.md) for exact evidence and pending gates. Local tests cover migration, settings actions, identity matching, cancellation/deadline handling, close success/failure/handoff, refresh coalescing, background disk loading, and search focus/caret behavior. Strict source compilation is also required. Temporary native-test entry points must never be committed or packaged.

Disposable native windows reproduced inaccessible AX state under Stage Manager. The fallback closed only the requested second window while preserving its three siblings and the app process. A separate disposable save-sheet test returned `confirmationRequired`; cancelling kept the window, confirming closed it. Native panel observations verified decoration removal and row-count reduction. These checks do not certify every app, real keyboard capture, other Spaces, or end-to-end frame pacing.

The release-build benchmark measures CPU query/layout/offscreen painting for 10/50/100 windows with grouping on/off. It does not measure input-to-display latency. Physical keyboard acceptance, unresponsive-app AX timing, cold/warm preview matrix, Reduce Motion, and available multi-display/high-refresh cases still belong to the release gate. Login approval/relogin is not validated here.

## Run and release

`scripts/build-app` builds the normal development app; quit the old process and launch `build/slime.app`. Restart after granting Accessibility or Screen Recording. If tap installation fails, interception is disabled while menu-bar settings remain usable; re-enable after permission/restart.

`scripts/package-dmg` builds release configuration and checks the mounted image, signature, metadata, icon, executable, architecture, and Applications link. The owner approved an unnotarized arm64 DMG signed with the local certificate. No Developer ID or universal validation is claimed. Do not disable Gatekeeper globally.

Next: resolve PR review findings, obtain the owner's merge, complete the outstanding release acceptance in #52, verify merged-main CI, rebuild the DMG from that commit, tag `v0.0.6`, publish DMG/checksum/release notes, and verify the downloaded asset. Do not publish before acceptance is complete.

## Remaining platform limits

AX can expose only some Spaces. Never-observed windows can be absent; ambiguous identities are refused. Previously preserved sibling windows closed outside slime can linger if WindowServer retains their surfaces (see System design). Preview disk filenames still use window IDs without cross-boot ownership metadata. The current text filter has no arbitrary caret positioning, clipboard editing, or IME composition. No private APIs or dependencies were added.
