import 'package:pov_agent/features/assistant/application/models/piper_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';

/// Audio plus the exact wall-clock interval that owned the native runtime.
///
/// Both timestamps originate on the worker isolate: creation is recorded only
/// after `OfflineTts` construction succeeds, and free is recorded only after
/// `OfflineTts.free()` returns.
final class PiperSpeechGeneration {
  /// Creates a completed generation whose native runtime has already freed.
  PiperSpeechGeneration({
    required this.audio,
    required this.runtimeCreatedAtUtc,
    required this.runtimeFreedAtUtc,
  }) {
    if (!runtimeCreatedAtUtc.isUtc || !runtimeFreedAtUtc.isUtc) {
      throw ArgumentError('Piper runtime lifecycle timestamps must be UTC.');
    }
    if (runtimeFreedAtUtc.isBefore(runtimeCreatedAtUtc)) {
      throw ArgumentError(
        'Piper runtime free cannot precede runtime creation.',
      );
    }
  }

  /// Owned mono PCM that remains valid after native runtime release.
  final GeneratedSpeechAudio audio;

  /// Worker timestamp immediately after successful native construction.
  final DateTime runtimeCreatedAtUtc;

  /// Worker timestamp immediately after successful native release.
  final DateTime runtimeFreedAtUtc;
}

/// Synthesizes one local utterance from a verified Piper model bundle.
// Native generation remains injectable so adapter tests never load sherpa-onnx.
// ignore: one_member_abstracts
abstract interface class PiperSpeechGenerator {
  /// Creates mono PCM for [text] and frees native model ownership before return.
  ///
  /// Lifecycle callbacks are delivered in order from the same worker event
  /// port. They make the live ownership window observable without pretending
  /// that isolate scheduling time is native construction time.
  Future<PiperSpeechGeneration> generate({
    required String text,
    required VerifiedPiperModelBundle bundle,
    required PiperRuntimeConfiguration configuration,
    required void Function(DateTime createdAtUtc) onRuntimeCreated,
    required void Function(DateTime freedAtUtc) onRuntimeFreed,
  });
}
