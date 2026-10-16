# Publishing a release

Release notes are written and reviewed in English. Bilingual notes are not required.
The workflow publishes the file unchanged; it never substitutes generated commit logs.

## Maintain notes in every PR

**Current unreleased version: [0.0.8](0.0.8.md). Version 0.0.7 is frozen.**

1. Every PR updates the current version's document in the same PR, including
   features, bug fixes, documentation, maintenance, and release preparation.
   Spec-focused PRs are exempt: omit their entries and apply `release-notes:skip`.
   Reviewers verify the PR primarily specifies future work; feature implementations,
   bug fixes, and ordinary documentation/maintenance PRs still require notes. If a
   spec PR grows into implementation, remove the label and add its entry. Supporting
   spec-workflow changes may stay in a spec-focused PR, as in #74.
   For each non-exempt PR, write one English bullet describing its final changes, crediting
   the **PR author** by GitHub username:

   ```markdown
   - Add selectable background themes. ([#62](https://github.com/chriscco/slime/pull/62)) — @chriscco
   ```

2. Open a draft PR to obtain its number, then add its entry before requesting
   review. Keep the entry accurate as the scope changes; consolidate rather than
   append another bullet for the same PR. Bot authors use `@name[bot]`.
3. Reviewers check the entry or spec exemption against the final diff before marking
   the PR Ready. The release validator excludes PRs labeled `release-notes:skip`;
   retain the reviewed label after merge so future release validation remains consistent.
   If another version is frozen before merge, move the entry to the new current
   version and recheck coverage.
4. Frozen version documents stay unchanged. After a version is frozen, the first
   subsequent PR creates the next version's document and updates the current-version
   link above. Carry forward any entries for PRs outside the frozen release into
   the new document, without changing the frozen file.

Development notes need a `# slime v<version>` heading, an `Unreleased.` status,
and a `## Changes` section. Finalize the remaining template sections at release
preparation; do not add development-version notices to the READMEs.

## Prepare the release

1. Finalize the current notes using [`../templates/release.md`](../templates/release.md):
   replace `Unreleased.` with a summary, add installation instructions and known
   limitations, and remove every placeholder.
2. Verify exactly one entry for every non-exempt PR merged into `main` since the
   preceding stable tag, including the preparation PR itself. Spec-focused PRs
   labeled `release-notes:skip` must have no entry. The validator checks coverage
   and usernames against GitHub; review checks wording and accuracy.
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
only tag actual releases. The existing merge-commit PR policy is required.

The workflow checks main ancestry and notes, runs release-script and Swift tests,
imports the signing identity, builds and inspects the DMG using `scripts/package-dmg`,
checks bundle/tag version equality, then uploads DMG + SHA-256 and publishes the notes.
Missing secrets, missing/incorrect PR entries, API failures, and version mismatch stop
publication. PR workflows run checks without access to release signing secrets.

## Failure recovery

- For transient service errors or missing secrets, fix the configuration and rerun
  the failed workflow. Do not move an existing version tag.
- `gh release create` uploads assets before publishing. A failed upload may leave a
  draft: inspect and remove that unpublished draft manually before retrying. Existing
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
