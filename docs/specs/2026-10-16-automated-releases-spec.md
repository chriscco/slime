# Tagged releases with reviewed notes

Approved direction: automatic publication after an owner-created stable tag,
with manually reviewed English notes. Tracked in #63; independent of the 0.0.7 UI PR.

## Contract

- Pushing `vX.Y.Z` runs the release workflow on macOS arm64. It must resolve to a
  commit already merged into `main`, with a version greater than the preceding
  stable tag on first-parent history.
- `docs/releases/X.Y.Z.md` is the exact Release body. Its heading matches the tag.
  A reusable English template lives at `docs/templates/release.md`.
- Each main-branch PR merged since the previous tag has exactly one descriptive
  bullet containing its full PR link and the PR author's GitHub username. This is
  the user's chosen meaning of committer, not the person who merged the PR.
  Git history and GitHub metadata validate coverage and authorship; review validates
  wording. Existing merge-commit-only repository policy remains required.
- Tests, notes checks, signing and existing DMG verification must pass. The bundle
  version must equal the tag before any publication. API failures fail closed.
- Import the stable self-signing identity from repository secrets into a temporary
  keychain. Missing credentials must not cause an ad-hoc release. Clean up afterwards.
- Publish the arm64 DMG and SHA-256 together with reviewed notes. Never overwrite
  an existing release or move its tag. Failed uploads may leave a draft requiring
  manual inspection/removal before retry; source fixes require a new tag.

## Scope and validation

No actual tag/release, certificate export/upload, Developer ID/notarization, Intel
package, translation requirement, or synthesized release descriptions in this PR.

Release-script tests use temporary Git repositories and mocked GitHub metadata;
signing tests cover required/explicit identities, failed signing and unchanged local
ad-hoc fallback. Run these in PR CI without release credentials, alongside Swift tests.
Verify local signed DMG packaging and workflow syntax. A future owner-created tag and
configured secrets are required to verify hosted signing and real publication.

## Implementation sequence

1. Reproduce missing validation with script tests; implement tag/history/note/bundle checks.
2. Add tag workflow, strict release signing and signing-policy tests; reuse existing packaging.
3. Add template and setup/recovery documentation, then verify tests/package/workflow and open an independent PR.
