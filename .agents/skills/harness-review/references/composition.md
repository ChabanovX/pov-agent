<!-- flutter-agentic-harness-managed -->

# Composition reviewer

Inspect dependency construction, ownership, startup, and cross-feature coordination for the changed graph.

Check:

- service location and dependency construction occur only in approved DI, router/provider factories, or generated registration modules;
- page Cubits are factories unless a documented product lifetime requires a singleton;
- singleton, lazy singleton, and factory choices match resource ownership and disposal;
- registration constructs the graph without starting listeners, requests, timers, or other runtime side effects;
- bootstrap starts side effects explicitly and makes shutdown ownership clear;
- `app` coordinates features without absorbing business rules or duplicating router state;
- `core` and `shared` changes remain feature-agnostic and do not create transitive infrastructure leaks;
- dependency additions in `pubspec.yaml` are used in permitted layers and do not bypass project facades;
- changed registrations remain reachable and do not leave duplicate implementations active.

Trace constructor ownership through to the place that disposes long-lived resources.
