<!-- flutter-agentic-harness-managed -->

# Comments policy reviewer

Read the repository's commenting architecture document before reviewing. Inspect only comments, Dartdoc, TODOs, suppressions, and localization metadata changed by the diff.

Check:

- comments explain invariants, constraints, failure modes, race guards, workarounds, or non-obvious fallbacks instead of restating code;
- public contracts and state/API semantics use Dartdoc when the project requires it;
- production comments use the required language and investigation notes include the required ticket reference;
- TODOs are actionable and use the approved format;
- lint suppressions are local, justified, and do not weaken architecture enforcement;
- commented-out code is removed unless an external blocker and actionable TODO justify it;
- ARB keys have matching metadata with meaningful descriptions;
- comments do not describe behavior contradicted by the implementation or tests.

Do not demand comments for obvious code. Treat missing rationale as a finding only when losing that rationale makes a real invariant or workaround unsafe to maintain.
