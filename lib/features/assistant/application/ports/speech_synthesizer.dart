import 'package:pov_agent/shared/domain/app_result.dart';

/// Speaks completed assistant comments through a foreground audio runtime.
///
/// Implementations are single-flight: callers must wait for [speak] to settle
/// or call [stop] before starting another utterance. No operation may enqueue
/// text behind an active utterance.
abstract interface class SpeechSynthesizer {
  /// Speaks [text] and settles after completion, interruption, or failure.
  Future<AppResult<void>> speak(String text);

  /// Stops active speech and settles after the native runtime is quiescent.
  Future<AppResult<void>> stop();

  /// Permanently stops speech and releases adapter-owned callback resources.
  ///
  /// A failed close retains native ownership and may be retried. A successful
  /// close is idempotent.
  Future<AppResult<void>> close();
}
