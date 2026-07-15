<!-- flutter-agentic-harness-managed -->

# Async state reviewer

Enumerate each affected public asynchronous Cubit/Bloc method and asynchronous event handler. Classify its concurrency policy as ignore, serialize, restart/latest-wins, or overlap; treat `isClosed` only as a lifecycle guard, never as proof of concurrency safety.

Check:

- overlapping calls cannot duplicate forbidden work or reorder mutations;
- an older result cannot overwrite state for a newer request, identifier, or query;
- every emit after an asynchronous gap is guarded against disposal;
- request tokens, cancellation, mutexes, or busy guards are structurally complete and reset on exceptions;
- timers, stream subscriptions, controllers, and callbacks are canceled or closed by their owner;
- state is immutable at publication boundaries, including collection aliasing;
- hidden mutable fields do not become a second, inconsistent state model;
- retry and failure paths preserve the selected concurrency policy;
- tests exercise the relevant interleaving rather than only the successful sequence.

Reason through at least the two-call interleaving for any method that can be invoked repeatedly. State the selected policy in `flow_summary`.
