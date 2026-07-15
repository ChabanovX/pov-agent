<!-- flutter-agentic-harness-managed -->

# Composition reviewer

Inspect dependency construction, ownership, startup, and cross-feature coordination for the changed graph.

Check:

- service location and dependency construction occur only in approved DI, router/provider factories, or generated registration modules;
- app and router constructors accept only app configuration and typed route data, never feature services, repositories, controllers, Cubits/Blocs, or UI factories;
- each dependency is resolved once at the nearest approved composition boundary instead of being passed unchanged through intermediate widgets that neither own nor use it;
- production constructors do not expose nullable DI overrides whose only purpose is injecting test doubles;
- test doubles enter through DI registration or a dedicated test composition rather than production constructor seams;
- concrete data adapters are never constructed from `State.initState()` or another widget lifecycle callback;
- `WidgetBuilder`, callbacks, and generic factories do not hide service location or bypass DI and layer boundaries;
- GetIt calls stay in approved composition code, while registered factories supply Cubit/Bloc constructor dependencies and state managers never locate dependencies themselves;
- page Cubits are factories unless a documented product lifetime requires a singleton;
- singleton, lazy singleton, and factory choices match resource ownership and disposal;
- registration constructs the graph without starting listeners, requests, timers, or other runtime side effects;
- bootstrap starts side effects explicitly and makes shutdown ownership clear;
- `app` coordinates features without absorbing business rules or duplicating router state;
- `core` and `shared` changes remain feature-agnostic and do not create transitive infrastructure leaks;
- dependency additions in `pubspec.yaml` are used in permitted layers and do not bypass project facades;
- changed registrations remain reachable and do not leave duplicate implementations active.

Trace constructor ownership through to the place that disposes long-lived resources.
