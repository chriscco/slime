# One-shot activation recovery

Issue #97. The owner approved this scope; implementation and spec share one PR.

- Preserve immediate app activation and the cached-target fast path.
- Only after a missing or failed cached target, read CG candidates and the selected
  application's AX snapshot once. Do not enumerate other applications.
- Retain native identity when known; never rebind a missing identity by title.
  Without an identity, require the existing unambiguous frame/title matching rules.
  Recheck the selected CG surface after AX reads.
- Attempt one recovered raise, then retain application fallback. No menu fallback,
  retry loop, deliberate delay, screenshot capture or increased timeout.
- Share the original 150 ms request budget, cancellation and generation guards.
  System IPC can exceed its requested timeout; this is not a hard wall-clock bound.
- User input or an external app switch cancels pending work. A recovery result must
  still match the requested PID/window ID. Only confirmed exact focus updates MRU.
- Record unresolved Chrome/partial-AX-list behavior as open defect #98; this change
  does not promise exact activation for every visible card.

Verification: cached success skips recovery; missing/failed targets recover once;
failed recovery falls back; cancellation prevents a recovered raise; wrong targets
are rejected. Run full tests and a release build. Native reported-window acceptance
remains separate from deterministic tests.
