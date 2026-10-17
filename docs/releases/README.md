# Publishing a release

Release notes are written and reviewed in English. Bilingual notes are not required.
The workflow publishes the file unchanged; it never substitutes generated commit logs.

## Review release-note scope in every PR

**Current unreleased version: [0.0.8](0.0.8.md). Version 0.0.7 is frozen.**

1. Record user-visible features, bug fixes, performance improvements, compatibility
   changes and installation/update behavior. Internal-only specs, documentation,
   behavior-preserving refactors, tests and CI maintenance may omit an entry.
   Apply `release-notes:skip` with a brief rationale in the PR; reviewers confirm
   the exemption. Remove the label if user-visible changes enter the scope.
2. For each included PR, write one English bullet describing the final user-visible
   result, linking the PR and crediting its author by GitHub username:

   ```markdown
   - Add selectable background themes. ([#62](https://github.com/chriscco/slime/pull/62)) — @chriscco
   ```

   Open a draft PR to obtain its number. Keep its entry accurate as scope changes;
   consolidate rather than duplicate bullets. Bot authors use `@name[bot]`.
3. Reviewers check relevant coverage, links, author credit or the skip rationale.
   Release CI does not enumerate merged PRs or compare GitHub authors/labels;
   omitted internal PRs and PR-metadata API outages cannot block publication.
4. Frozen version documents stay unchanged. The first subsequent PR requiring
   notes creates the next version's document and updates the current-version link.
   Carry forward changes outside the frozen release into that new document.

Development notes need a `# slime v<version>` heading, an `Unreleased.` status,
and a `## Changes` section. Finalize the remaining template sections at release
preparation; do not add development-version notices to the READMEs.

## Prepare the release

1. Finalize the current notes using [`../templates/release.md`](../templates/release.md):
   replace `Unreleased.` with a summary, add installation instructions and known
   limitations, and remove every placeholder.
2. Review user-visible changes since the preceding stable tag and include the
   relevant PRs with accurate links and author credit. Internal-only PRs may be
   omitted; there is no exact-coverage requirement in release CI.
3. Update `CFBundleShortVersionString` and `CFBundleVersion` in `scripts/build-app`.
   Review the notes and native acceptance results in the PR, then have the owner merge.

## One-time signing setup

The workflow builds an **arm64, self-signed, unnotarized** DMG on `macos-26`.
A stable signing identity is required; release builds never fall back to ad-hoc.
Configure these repository Actions secrets before pushing the first release tag:

| Secret | Value |
|---|---|
| `RELEASE_CERTIFICATE_BASE64` | Base64 of a password-protected `.p12` containing the existing `slime Local Signing` certificate **and private key**. |
| `RELEASE_CERTIFICATE_PASSWORD` | The nonempty password used to export that `.p12`. |
| `RELEASE_SIGNING_IDENTITY` | Its 40-character SHA-1 code-signing identity from `security find-identity -v -p codesigning`. |

Export only this identity in Keychain Access, then upload through GitHub repository
**Settings → Secrets and variables → Actions** (or `gh secret set` reading files/stdin).
Do not commit credentials, paste them into PRs, or print them in logs. Use the same
identity as existing releases to retain signing continuity; do not generate a new
certificate on each runner. No credentials are automatically exported from a developer's Mac.
The workflow imports private keys into a temporary keychain and deletes it even when
a later step fails. Its CI-only helper requires a GitHub-hosted runner. It trusts the
public self-signed certificate for code signing in that disposable VM's administrator
store using noninteractive sudo; it does not change authorization rules. The VM's
public trust entry disappears when GitHub discards the runner.

Import has a two-minute step timeout and reports each stage without secret values.
PR CI tests the same helper with a generated, one-day certificate and verifies a real
signed executable; it never reads production signing secrets.

This does not add Developer ID signing or notarization. If that distribution policy
changes, update signing and the installation text together.

## One-time Sparkle update signing setup

Sparkle **2.10.0** is pinned in SwiftPM, including the distribution checksum and its
`generate_keys`, `generate_appcast`, and `sign_update` tools. Update signing is separate
from the existing code-signing certificate. Keep the three `RELEASE_*` secrets above.
The owner must configure these additional Actions values before an updater-enabled release:

| Type | Name | Value |
|---|---|---|
| Repository variable | `SPARKLE_PUBLIC_KEY` | Base64 Ed25519 public key printed by Sparkle. |
| Repository secret | `SPARKLE_PRIVATE_KEY` | Contents of Sparkle's exported private key file. |

After `swift package resolve`, the owner can run the pinned tool once on a trusted Mac:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account slime
```

Record its public key as the repository variable. Export the matching key using
`generate_keys --account slime -x <protected-private-key-file>`, from a directory only
the owner can read (`umask 077`). Upload the file through GitHub Actions secret settings
or `gh secret set SPARKLE_PRIVATE_KEY < /secure/path/slime-update-private-key`. Keep a secure
offline backup and remove the temporary export. Never paste the private key into a
command argument, issue, PR, or log. Key creation/export is an owner setup action;
packaging and CI do not generate or replace production keys.

`scripts/sign-updates vX.Y.Z` reads the private key from the environment, removes it
from child environments, and passes it to official Sparkle tools through stdin. It
uses a fresh temporary directory, embeds the reviewed English notes, checks the bundle
version, minimum macOS version, arm64 requirement, immutable HTTPS archive URL and size,
then verifies both archive and feed signatures. The generator only signs an archive
when its bundled public key matches the supplied private key. Missing or mismatched
keys stop publication. The temporary directory is removed on success or failure.

Local builds can omit `SPARKLE_PUBLIC_KEY`; they embed Sparkle but have no feed/key,
and settings reports updates unavailable. Local release configuration works the same
way. CI sets `REQUIRE_UPDATES=1` and requires a valid public key; feed generation also
requires the private key. Automatic checks and downloads default off, profiling is
disabled, and both signed feeds and archive verification before extraction are required.

The stable feed is
`https://github.com/chriscco/slime/releases/latest/download/appcast.xml`; each enclosure
uses its immutable `/releases/download/vX.Y.Z/slime-X.Y.Z-arm64.dmg` URL. Feed and archive
are authenticated independently with Ed25519. Keep all future stable releases on this
pipeline, since publishing a newer release without `appcast.xml` would break the latest
feed endpoint. GitHub's initial 404 before the first updater release is expected.
Version 0.0.7 has no updater, so the first updater-enabled release must be installed
manually. Signing does not add notarization or eliminate macOS opening prompts.

References: [Sparkle integration and signing](https://sparkle-project.org/documentation/),
[pinned appcast key matching](https://github.com/sparkle-project/Sparkle/blob/2.10.0/generate_appcast/Appcast.swift),
[pinned signing tool](https://github.com/sparkle-project/Sparkle/blob/2.10.0/sign_update/main.swift).

## Publish

From a clean, up-to-date `main`, after owner acceptance:

```sh
git pull --ff-only origin main
scripts/test
git tag -a v0.0.8 -m 'slime v0.0.8'
scripts/check-release v0.0.8 --repository chriscco/slime
git push origin v0.0.8
```

Use the intended version in place of `0.0.8`. Only stable `vX.Y.Z` tags are supported.
The notes range starts at the nearest preceding version tag on first-parent history;
only tag actual releases.

The workflow checks main ancestry and notes, runs release-script and Swift tests,
imports the signing identity, builds and inspects the DMG using `scripts/package-dmg`,
checks bundle/tag version equality, signs/verifies the archive and appcast, then uploads
DMG + SHA-256 + appcast in the same `gh release create` call and publishes the notes.
Missing secrets, invalid tag ancestry/version progression, missing or malformed notes,
and bundle-version mismatch stop publication. PR coverage and attribution are review concerns. PR workflows run checks without access to release signing secrets.

## Failure recovery

- For transient service errors or missing secrets, fix the configuration and rerun
  the failed workflow. Do not move an existing version tag.
- `gh release create` uploads assets before publishing. A failed upload may leave a
  draft: the previous published latest feed remains in place. Inspect and remove that
  unpublished draft manually before retrying. Existing
  releases/assets are never overwritten automatically.
- Rerunning an existing tag's failed run uses that tag's original workflow, not a
  subsequently fixed workflow from `main`. A signing-workflow fix therefore cannot
  repair an old run just by clicking Re-run. Keep the tag fixed; agree on a separate
  recovery publication from its exact source or prepare a new version/tag.
- If source or notes need changes, merge a fix and prepare a **new version/tag**.
- Automated packaging does not certify Accessibility prompts, window behavior, or
  visual acceptance on a user's desktop. Complete native checks before pushing a tag.

References: [GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[certificate import](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[release creation](https://cli.github.com/manual/gh_release_create).
