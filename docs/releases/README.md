# Publishing a release

Release notes are written and reviewed in English. Bilingual notes are not required.
The workflow publishes the file unchanged; it never substitutes generated commit logs.

## Prepare the notes

1. Copy [`../templates/release.md`](../templates/release.md) to `<version>.md` in
   this directory (for example, `0.0.7.md`). Replace every placeholder.
2. Include exactly one bullet for every PR merged into `main` since the preceding
   stable version tag, including documentation/maintenance and release preparation.
   Use this format, crediting the **PR author** by GitHub username:

   ```markdown
   - Add selectable background themes. ([#62](https://github.com/chriscco/slime/pull/62)) — @chriscco
   ```

   Open the preparation PR first so its own number is available for the notes.
   The validator checks PR coverage and usernames against GitHub; editorial quality
   and English wording are checked in review. Bot authors use `@name[bot]`.
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
git tag -a v0.0.7 -m 'slime v0.0.7'
scripts/check-release v0.0.7 --repository chriscco/slime
git push origin v0.0.7
```

Use the intended version in place of `0.0.7`. Only stable `vX.Y.Z` tags are supported.
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
