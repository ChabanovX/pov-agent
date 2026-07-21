🥀 Milestone 4 is implemented, merged into `main`, and pushed to GitHub.

- Merge commit: `b9bc6b8`
- Full harness passed twice on the feature and merged trees: 199 tests, analyzer, architecture, quality, formatting, goldens, and Bloc lint.
- Wired iPhone live-camera inference passed with Metal GPU enabled.
- The corrected full 10-minute device soak is deferred to the final milestone, as requested. The partial corrected Simulator run completed 29 comments with a 3.653s worst latency.
- The unrelated [.vscode/settings.json](.vscode/settings.json) remains untouched.
- The clean feature worktree was retained because Git refuses to remove worktrees containing an initialized submodule.

Key implementation areas: [observer_bloc.dart](lib/features/assistant/presentation/bloc/observer_bloc.dart), [observer_prompt_builder.dart](lib/features/assistant/application/services/observer_prompt_builder.dart), [assistant_page.dart](lib/features/assistant/presentation/pages/assistant_page.dart), [app_runtime.dart](lib/app/bootstrap/app_runtime.dart), and [observer_native_soak_test.dart](integration_test/observer_native_soak_test.dart).

You can disconnect the iPhone.