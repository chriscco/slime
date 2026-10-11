---
name: pr-review
description: Review a pull request against its linked issue/spec and repository rules, then produce or post a concise review comment with a Ready, Ready-with-fixes, or Not-Ready verdict. Use for PR review, re-review, or review-comment requests in this repository.
---

# PR Review

Review the PR diff against two independent sources:

- **Spec**: the linked issue, spec, and stated PR scope.
- **Standards**: repository instructions that apply to the changed files.

Honor a narrower user request such as “只看 spec”. Read the full diff and every
relevant source before assigning a verdict. Report only findings introduced or
left unresolved by the PR; skip style preferences and issues enforced by tooling.

## Verdict

- **Ready** — mergeable as-is; no required fixes.
- **Ready-with-fixes** — only bounded, mechanical fixes remain; merge after those
  fixes, without another design decision or full re-review.
- **Not-Ready** — correctness, security, data-loss, or core-spec problems remain;
  the PR needs substantive changes and another review.

The verdict follows the worst required finding. Known limitations count as
resolved only when the issue/spec explicitly accepts them and callers can observe
or safely handle them; silently converting “unknown” into a valid value is still
a finding.

## Test gate

Tests are a required review axis:

1. For every behavior change, verify that a test exercises the changed behavior
   through a public interface. Documentation-only and static-configuration changes
   may omit new tests.
2. Run `scripts/test` locally when the repository is available.
3. Check the `test` GitHub Actions job for the reviewed head commit. Never infer a
   CI pass from a local pass or from an older commit.

`Ready` and `Ready-with-fixes` both require the local test command and the current
head's CI `test` job to pass. A missing, pending, skipped, cancelled, or failed CI
test job makes the verdict `Not-Ready`. Missing behavior coverage is a required
finding even when CI is green.

## Findings

Order findings by severity. Each finding must contain:

1. priority (`P0`–`P3`) and a short title;
2. exact file/location;
3. the failing scenario and observable impact;
4. the smallest adequate fix.

Do not invent findings to fill a section. A re-review states which previous
findings are closed, partial, or open, then reports only remaining blockers.

## Comment format

Every PR review comment starts with:

```markdown
## Verdict: Ready | Ready-with-fixes | Not-Ready

<One sentence explaining why.>

## Tests

- Local: Pass | Fail | Not run
- CI (`test`): Pass | Fail | Pending | Missing
```

Then add only the non-empty sections needed:

```markdown
## Required fixes

- **[P1] Title** — `path:line`. Scenario, impact, and smallest fix.

## Notes

- Non-blocking observation.
```

The `Tests` section is always present. For `Ready`, no other section is needed.
Keep the comment self-contained. Post it only when the user explicitly asks to
comment or review on the hosting service; otherwise return the same text in chat.
