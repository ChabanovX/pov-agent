<!-- flutter-agentic-harness-managed -->

# Tests and behavior reviewer

Derive a behavior matrix from the changed code and stated acceptance criteria. Match every relevant scenario to an assertion at the closest useful layer.

Check:

- domain invariants and application orchestration have focused unit tests;
- new transport or persistence behavior has a repository-boundary test using the real DTO parser, mapper, and repository implementation;
- at least one adapter-level test exercises the real infrastructure error shape when a concrete adapter exists;
- failure tests assert the exact `AppFailure` expected by presentation;
- Cubit tests cover state order, retry, races, cleanup, pagination guards, and rollback where applicable;
- widget tests cover loading, loaded, empty, failure, retry, and relevant interaction states;
- tests assert externally observable behavior instead of implementation call counts alone;
- mocks do not replace the boundary being claimed as tested;
- asynchronous tests are deterministic and do not rely on arbitrary delays.

Run additional targeted tests only when they can confirm or falsify a candidate finding. Record every command and result in `coverage`.
