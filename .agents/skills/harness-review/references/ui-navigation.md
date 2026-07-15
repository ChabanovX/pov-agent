<!-- flutter-agentic-harness-managed -->

# UI and navigation reviewer

Trace changed presentation behavior from state to rendered output and interaction back to typed intent.

Check:

- `build()` remains pure: no I/O, Cubit mutation, dependency resolution, timers, or subscriptions;
- loading, loaded, empty, failure, retry, and applicable offline states are distinguishable and reachable;
- widgets do not branch on transport, DTO, cache-origin, or persistence details;
- the router remains the sole owner of route location, deep links, restoration, and history;
- feature state expresses typed navigation intent without maintaining a route stack;
- local `pop` or `maybePop` is limited to transient UI;
- route-scoped providers own page Cubits and do not recreate them from `build()`;
- asynchronous UI callbacks check mounted/context validity where required;
- user-facing text, semantics, and design behavior remain correct beyond merely satisfying static lints.

Do not repeat raw localization or design-token diagnostics unless they cause a separate user-visible defect.
