<!-- flutter-agentic-harness-managed -->

# Review contract

Review only the supplied change and the minimum surrounding code needed to prove its behavior. Report an existing problem as pre-existing context unless the change makes it reachable, more severe, or harder to remove.

## Evidence standard

Report a finding only when all of these are present:

- a concrete violated project contract or observable correctness requirement;
- source or test evidence at a named symbol;
- a reachable consequence;
- an actionable direction that does not require guessing product intent.

Put unresolved assumptions under `questions`, not `findings`. Do not report style preferences already handled by formatter, analyzer, architecture, or quality diagnostics unless they reveal a separate semantic defect.

## Severity

- `blocker`: likely data loss, security or privacy exposure, crash loop, unrecoverable workflow, or a release-blocking correctness failure.
- `major`: reachable behavior regression, stale-state race, raw infrastructure error leak, resource leak, incorrect lifetime, or missing required behavior coverage.
- `minor`: bounded maintainability or contract issue with a credible future failure mode but no immediate severe regression.
- `nit`: explicit project convention violation with negligible runtime impact. Use sparingly.

## Confidence

- `high`: directly demonstrated by code, test, or command output.
- `medium`: strongly supported but depends on one stated assumption.
- `low`: plausible but not publishable without additional evidence; normally return it as a question.

## Worker output

Return this shape:

```yaml
coverage:
  checked: []
  not_checked: []
flow_summary: []
findings:
  - title: ""
    severity: major
    confidence: high
    introduced: true
    contract: ""
    evidence:
      path: "relative/path.dart"
      symbol: "Type.member"
      line: 1
    impact: ""
    suggested_direction: ""
questions: []
```

Use repository-relative Markdown links in human-facing prose. Never append line numbers to link targets; mention the line separately. Return `findings: []` explicitly when no defect is proven. Do not edit files or create commits.

A role reference may require an additional top-level section for its evidence.
Return that section without removing or renaming any common field above.
