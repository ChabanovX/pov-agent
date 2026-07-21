import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Plays one generated PCM utterance without persisting its bytes.
///
/// Implementations are single-flight. [stop] interrupts the active utterance,
/// while [close] permanently releases player-owned native resources.
abstract interface class GeneratedSpeechAudioPlayer {
  /// Plays [audio] through terminal completion or interruption.
  Future<AppResult<void>> play(GeneratedSpeechAudio audio);

  /// Interrupts active playback and waits until output is quiescent.
  Future<AppResult<void>> stop();

  /// Stops playback and permanently releases the player.
  Future<AppResult<void>> close();
}
