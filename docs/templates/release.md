# slime v{{VERSION}}

{{One sentence describing the main benefit of this release.}}

## Changes

<!-- Include user-visible changes since the preceding stable version tag.
Internal specs/docs/refactors/tests/CI-only PRs may be omitted with a reviewed
release-notes:skip label (see docs/releases/README.md).
Use the PR author's GitHub username, not the merger or Git commit identity.
Keep the exact link/credit format below; replace every placeholder before tagging.
Write the description in English and explain the user-visible result. -->

- {{Description of the change.}} ([#{{PR_NUMBER}}](https://github.com/chriscco/slime/pull/{{PR_NUMBER}})) — @{{PR_AUTHOR}}

## Installation

Requires macOS 26 or later and Apple silicon.

Download `slime-{{VERSION}}-arm64.dmg` and its `.sha256` file, then verify:

```sh
shasum -a 256 -c slime-{{VERSION}}-arm64.dmg.sha256
```

Open the DMG and drag slime to Applications. The app is self-signed and not
notarized by Apple. If macOS blocks it, use **System Settings → Privacy & Security
→ Open Anyway** for slime. Grant Accessibility permission and restart; Screen
Recording permission is optional and enables window previews.

## Known limitations

{{Describe limitations that matter for this version, or write “None newly identified.”}}
