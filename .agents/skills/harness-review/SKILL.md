---
name: harness-review
description: Review a Flutter branch or working tree against the installed Flutter Agentic Harness contract with specialized read-only subagents for boundaries, async state, UI and navigation, tests, composition, comments, and finding verification. Use only when the caller explicitly invokes $harness-review.
---

<!-- flutter-agentic-harness-managed -->

# Harness Review

Perform an evidence-based review of the current change. Report findings only; do not modify files, create commits, or expand the requested review into implementation work.

## 1. Establish the review scope

1. Read the repository-root `AGENTS.md` and every architecture document it requires for the changed paths.
2. Use a base ref named by the caller. Otherwise read `verification.changed_base` from `.agent_harness.yaml`, falling back to `origin/main` only when the setting is absent.
3. Verify that the base ref exists before reviewing committed branch changes. If it does not exist, ask for a valid base instead of silently reviewing a partial diff.
4. Collect committed changes from `base...HEAD`, tracked working-tree changes from `HEAD`, and untracked files. Deduplicate the paths.
5. If the scope is empty, report that no changes were available and stop without spawning reviewers.

## 2. Run deterministic preflight

Run `dart run tool/harness.dart verify --changed --base <base>` once from the project root. Preserve its exit code and concise failure output. Continue semantic review when preflight fails; treat its diagnostics as evidence, not as a substitute for reviewer reasoning.

Read [references/review-contract.md](references/review-contract.md) before delegating. Give each reviewer:

- the raw diff and changed-file list;
- the applicable `AGENTS.md` and architecture documents;
- relevant callers, callees, and nearest tests;
- the preflight summary;
- the common review contract and exactly one role reference.

Do not pass another reviewer's conclusions to an independent first-pass reviewer.

## 3. Select reviewers

Use project-scoped custom agents when the runtime exposes them. Otherwise spawn a default read-only subagent and instruct it to read the same role reference.

| Agent | Role reference | Select when |
|---|---|---|
| `harness-boundary-flow` | [references/boundary-flow.md](references/boundary-flow.md) | Production code under feature, app, core, or shared roots changed |
| `harness-async-state` | [references/async-state.md](references/async-state.md) | Cubit, Bloc, state, async operation, timer, stream, or subscription code changed |
| `harness-ui-navigation` | [references/ui-navigation.md](references/ui-navigation.md) | Presentation, widget, page, router, design-system, asset, or localization code changed |
| `harness-tests-behavior` | [references/tests-behavior.md](references/tests-behavior.md) | Product behavior or its tests changed |
| `harness-composition` | [references/composition.md](references/composition.md) | DI, bootstrap, router composition, core/shared contracts, repository registration, or dependencies changed |
| `harness-comments-policy` | [references/comments-policy.md](references/comments-policy.md) | The diff changes comments, Dartdoc, TODOs, suppressions, or ARB metadata |

Select every applicable role, but keep at most three worker agents active at once. Use direct child agents only and forbid workers from spawning descendants. Run additional roles in later waves. When subagents are unavailable, perform the selected role passes sequentially in the main thread.

## 4. Verify candidate findings

If no worker reports a candidate finding, skip the verifier. Otherwise run `harness-finding-verifier` with:

- the raw diff and relevant source context;
- every candidate finding without reviewer identity;
- [references/finding-verifier.md](references/finding-verifier.md);
- the common review contract.

Require the verifier to accept, reject, merge, downgrade, or reclassify every candidate. Do not publish rejected findings. Resolve remaining conflicts in the main thread from source evidence.

## 5. Report

Return:

1. verified findings ordered by severity, then confidence;
2. each finding's contract, evidence, impact, and suggested direction;
3. pre-existing concerns separately from introduced or worsened findings;
4. reviewer coverage and explicit gaps;
5. preflight and targeted commands run with their results.

Say `No verified findings` when appropriate. Do not claim that a clean static preflight proves semantic correctness.
