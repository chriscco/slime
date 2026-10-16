# App handoff — background compatibility (PR #78)

## Current state

PR #78 includes the spec and implementation independently of #75/#76. It adds
material selection on macOS 26+, opaque fallback on macOS 15, and shared settings.
The package and bundle target 15; compilation still needs a macOS 26+ SDK. Saved
Glass preferences survive unsupported systems, and Solid does not erase glass values.

## Integration

Reconcile shared settings/build files with #76 when it merges. Its appcast generation
reads LSMinimumSystemVersion from the packaged bundle; retain that behavior and the
15.0 bundle floor. Retain Sparkle packaging/signing and its independently valid minimum.
Keep #75 preview source controls alongside the material controls.

## Verification

Local tests exercise material resolution, actual hosts, opacity/theme colors, settings
controls, query/selection preservation, and no window refresh on material changes.
A macOS 15 CI lane runs tests, builds an ad-hoc signed bundle, verifies its Mach-O/plist
minimum, and checks five-second startup with interception disabled. This is not TCC
acceptance. See the PR checks for exact current-head results.

## Remaining native acceptance

macOS 15 remains experimental: startup with real permission grants, optional screenshot
permission, Stage Manager, Spaces/multiple displays, activation and close operations need
an external tester. The development host is macOS 27, not 15/26. Do not describe a green
CI run as completion of those native checks. User performs the merge; no tag/release.
