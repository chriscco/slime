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
an external tester. The development host is macOS 27. The macOS 26+ visible-window material check is
also pending: computer-use inspection timed out and offscreen native controls did not
composite reliably. Do not describe a green CI run as completion of these checks. User performs the merge; no tag/release.


## Implementation evidence

Implementation head `55f8123` passed 183 local Swift tests and 12 script tests, plus
signed release packaging and the five-second launch smoke check. CI run
[38878926193](https://github.com/chriscco/slime/actions/runs/38878926193) passed `test`,
`signing`, and `compatibility` (macOS 15). The first compatibility run found an old
87%-opacity assertion; it now expects opaque Solid on 15. No product workaround was needed.

A disposable integration with #76 passed 190 Swift tests, 18 script tests, signed
release packaging, and launch smoke. Resolve Package.swift by retaining the 15 minimum
and Sparkle dependency; retain both sets of settings initializer parameters/properties;
combine design/decision/handoff documentation. These temporary resolutions were not
merged into either PR branch. No release, tag, or update key changes were made.
