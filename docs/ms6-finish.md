# Milestone 6 acceptance record

> **Status:** complete. The host, emulator, and iPhone 11 acceptance gates
> below pass on the finished implementation.

## Intended outcome

Automatic observer comments use the pinned
`vits-piper-en_US-ljspeech-medium-int8` voice through `sherpa_onnx` as the
primary English speech backend. The existing system TTS adapter remains a
technical fallback only when local speech fails before playback starts. Stop,
replay, mute, lifecycle cancellation, and stale-utterance suppression continue
to use the existing `SpeechSynthesizer` contract.

The implementation is split across explicit ownership boundaries:

- [verified_piper_model_store.dart](../lib/features/assistant/data/repositories/verified_piper_model_store.dart)
  owns staged download, archive verification, extraction, tree verification,
  cache reuse, suspension, and close.
- [sherpa_piper_speech_generator.dart](../lib/features/assistant/data/ffi/sherpa_piper_speech_generator.dart)
  creates, uses, and frees the native Piper runtime on a worker isolate.
- [piper_speech_synthesizer.dart](../lib/features/assistant/data/adapters/piper_speech_synthesizer.dart)
  serializes model preparation, synthesis, playback, stop, and close.
- [fallback_speech_synthesizer.dart](../lib/features/assistant/data/adapters/fallback_speech_synthesizer.dart)
  prevents fallback after playback or an intentional stop.
- [just_audio_generated_speech_player.dart](../lib/features/assistant/data/adapters/just_audio_generated_speech_player.dart)
  converts generated PCM to an in-memory WAV stream; utterance audio is never
  written to persistent storage.
- [app_di.dart](../lib/app/di/app_di.dart) selects the complete runtime graph at
  the composition root.

## Model acquisition and configuration

The checked [`.env.example`](../.env.example) pins both acquisition and runtime
policy as compile-time values. The archive is 21,090,429 bytes (about 21 MB),
the expanded tar is exactly 37,662,720 bytes (about 38 MB), and the regular
files in the extracted bundle total 37,347,875 bytes (about 37 MB). Storage
preflight includes all concurrent artifacts plus the configured reserve. The
store owns and always removes the expanded staging tar. A cache becomes ready
only after the archive length and SHA-256 and the canonical extracted tree
size, file count, and SHA-256 all match the manifest. Later playback may reuse
that verified cache with transport disabled.

Provider, thread count, speaker ID, VITS noise and length scales, speed, silence
scale, sentence limit, and debug logging are also compile-time settings. A
malformed value fails during dependency composition rather than at the native
FFI boundary.

## Runtime and fallback contract

Synthesis returns PCM only after the worker isolate has freed the sherpa-onnx
runtime. Playback therefore does not overlap Piper model ownership with its own
audio resources. Stop invalidates the active utterance before waiting for
download, synthesis, or playback to quiesce, so a late failure cannot start the
system fallback.

Fallback is allowed for a technical failure that occurs before local audio is
heard, including acquisition, verification, synthesis, or playback startup.
Once local playback has started, its failure is terminal for that utterance;
the system backend must not repeat a partially heard sentence.

## Acceptance gates

- [x] `dart run tool/harness.dart verify --changed` passes on the finished
  diff.
- [x] A real repository-boundary test proves download, archive verification,
  extraction, full-tree verification, verified offline reuse, and corrupt-cache
  recovery.
- [x] iOS Simulator end-to-end acceptance proves real synthesis, non-silent
  PCM, in-memory playback completion, stop/replay, and offline cache reuse.
- [x] Android Emulator end-to-end acceptance proves the same production path.
- [x] iPhone 11 hardware smoke runs YOLO, Qwen, Piper synthesis, and playback
  together without memory termination and confirms the native runtime is freed
  before playback.
- [x] Independent semantic reviews report no unresolved blocker or major
  findings.

The host suite contains 290 passing tests. On 2026-07-21,
`tool/verify_piper_ios.sh` passed on the iPhone 12 Simulator with one cold Piper
download, 22,050 Hz non-silent PCM, YOLO progress during synthesis and playback,
stop/replay, and a transport-disabled restart. `tool/verify_piper_android.sh`
passed the same scenario on the stable API 36 arm64 emulator.
`tool/verify_piper_device_ios.sh` then passed on the iPhone 11 running iOS
18.7.8. The physical lane recorded one cold Piper download, 103,168 generated
samples at 22,050 Hz with a non-zero peak, YOLO progress across synthesis and
playback, one ObserverBloc-driven Qwen-to-Piper utterance, same-graph replay,
and transport-disabled restart without another Qwen or Piper download.

## Distribution consideration

The selected
[LJSpeech voice model card](https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/ljspeech/medium/MODEL_CARD)
lists its dataset license as public domain. Piper models use eSpeak NG data for
phonemization, as documented by the
[sherpa-onnx Piper guide](https://k2-fsa.github.io/sherpa/onnx/tts/piper.html).
That is a separate distribution concern:
[eSpeak NG is licensed GPL-3.0-or-later](https://github.com/espeak-ng/espeak-ng#license-information).
The public-domain voice status therefore does not remove the need to review and
satisfy the eSpeak NG terms before distributing an application binary that
contains the phonemizer data or runtime.
