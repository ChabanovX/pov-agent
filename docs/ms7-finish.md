# Milestone 7 completion: hands-free agent

Milestone 7 closes the foreground voice loop on iOS:

```text
microphone → streaming ASR → wake phrase → question → scene-aware Qwen
  → Piper playback → ASR re-arm
```

## Runtime shape

- The pinned NeMo FastConformer CTC int8 archive is downloaded, staged,
  length-checked, SHA-256 verified, extracted, and complete-tree verified by a
  typed `ModelStore` implementation shared with the established model lifecycle.
- `record` supplies mono PCM16 at 16 kHz behind the application-owned audio
  source boundary. User audio is bounded in memory and is never persisted.
- One persistent sherpa-onnx worker isolate owns the streaming recognizer. Its
  bounded input queue rejects overload instead of allowing unbounded PCM growth.
- `ObserverBloc` serializes wake detection, listening, Qwen generation, and
  Piper playback. Recognition is suspended while generation or TTS owns the
  foreground turn, so the agent cannot transcribe its own answer and barge-in
  remains outside the MVP.
- Lifecycle pause, permission denial, silence, empty transcripts, native ASR
  failures, model acquisition failures, and input failures project recoverable
  presentation states with explicit retry.

Compile-time artifact, integrity, runtime, decoder, endpoint, queue, and wake
phrase values live in [`.env.example`](../.env.example). App composition parses
the raw Qwen, Piper, and ASR groups once and supplies typed policies to the
feature; presentation does not import plugins, data adapters, or the service
locator.

## Verification

The deterministic fixture in
[`assets/audio/README.md`](../assets/audio/README.md) crosses the same native
recognizer as live input. The only substituted boundary is microphone capture.
The native test then requires a real YOLO scene, one committed question, a
non-empty Qwen answer without reasoning markup, the complete voice phase order,
and a completed Piper playback.

Completed gates:

- iOS Simulator: recognized “what can you see in front of the camera,” retained
  four scene objects, generated a 186-character answer, and completed one Piper
  playback.
- iPhone 11 on iOS 18.7.8: A13 Metal Qwen, four scene objects, the deterministic
  question, a 58-character answer, and one completed Piper playback.
- iPhone 11 live microphone: wake detection and streaming ASR recognized “what
  can be see in front of the camera,” Qwen generated a 182-character answer, and
  Piper completed playback before ASR re-armed.
- `dart run tool/harness.dart verify --changed`: analyzer, architecture,
  quality, 373 tests, goldens selection, and Bloc lint all passed.

Run the lanes with:

```sh
tool/verify_hands_free_ios.sh <simulator-id>
tool/verify_hands_free_device_ios.sh <physical-device-id>
tool/verify_hands_free_live_device_ios.sh <physical-device-id>
```
