🥀 Milestone 5 is complete, merged, and synchronized with GitHub.

## Outcome

Automatic observer comments now use native `en-US` text-to-speech with:

- Global mute.
- Per-comment stop and replay.
- No speech for drafts, failures, or manual answers.
- No stale comment queue.
- Safe manual-prompt preemption.
- Lifecycle and native audio-session recovery.

The architecture remains application port → data adapter → app-owned DI/runtime → presentation policy:

- [speech_synthesizer.dart](lib/features/assistant/application/ports/speech_synthesizer.dart)
- [flutter_tts_speech_synthesizer.dart](lib/features/assistant/data/adapters/flutter_tts_speech_synthesizer.dart)
- [observer_speech_policy.dart](lib/features/assistant/presentation/bloc/observer_speech_policy.dart)
- [observer_lifecycle_policy.dart](lib/features/assistant/presentation/bloc/observer_lifecycle_policy.dart)
- [app_runtime.dart](lib/app/bootstrap/app_runtime.dart)

## Real-device finding

The iPhone 11 exposed a transient `AVAudioSession` release rejection absent from both simulators. The fix now:

- Serializes session release.
- Retries only native rejections, not timeouts or exceptions.
- Cancels the utterance watchdog before teardown.
- Preserves ownership for retryable close failures.
- Bounds all retry attempts.

That correction is covered by 22 adapter tests in [flutter_tts_speech_synthesizer_test.dart](test/features/assistant/data/flutter_tts_speech_synthesizer_test.dart).

## Validation

- Full harness: 234 tests, formatting, analysis, architecture, quality, and Bloc lint passed.
- iOS Simulator native speech: 2/2 passed.
- Android API 36 ARM64 emulator platform lane passed.
- Physical iPhone 11 native speech: 2/2 passed.
- Live iPhone camera → YOLO → Metal Qwen → speech passed.
- Ten-minute iPhone soak passed:
  - 37 comments
  - 3,116 frames
  - 9.026-second slowest comment
  - 31.1 MiB sampled peak RSS growth
  - Clean native teardown
- Independent architecture, native-platform, race, and cold reviews found no remaining issues.

Acceptance coverage lives in [system_speech_native_test.dart](integration_test/system_speech_native_test.dart).

## Git

Atomic stack:

1. `ca08b7e feat(speech): add native system speech boundary`
2. `2eabfd0 feat(observer): add spoken comment controls`
3. `4396798 test(speech): add native emulator acceptance`
4. `e3689d7 docs(speech): document system speech milestone`
5. `b05be7b fix(speech): retry transient iOS session release`

Merged through [GitHub PR #1](https://github.com/ChabanovX/pov-agent/pull/1) with two-parent merge commit:

`d2ed61e merge: integrate system speech`

Local `main` and `origin/main` are synchronized and clean. The isolated Milestone 5 worktree was removed; its feature branch remains available locally and remotely for recovery or audit.