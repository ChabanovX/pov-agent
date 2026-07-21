import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// One live microphone-to-transcript session.
///
/// A handle owns a single microphone capture stream. Explicit reset preserves
/// capture while starting a new tagged recognition segment. A successful
/// [stop] is idempotent and closes [events] after native decoding settles.
abstract interface class SpeechRecognitionHandle {
  /// Tagged cumulative hypotheses, endpoints, and normalized failures.
  Stream<SpeechRecognitionEvent> get events;

  /// Resets native decoding and advances to the next segment.
  Future<AppResult<void>> resetForNextSegment();

  /// Stops capture, drains accepted audio, and releases the native stream.
  Future<AppResult<void>> stop();
}

/// Loads and runs one verified on-device streaming speech recognizer.
///
/// The recognizer is single-flight: [start] rejects while a previous handle is
/// active. [unload] stops that handle before releasing model memory. Failed
/// native unload or close operations retain ownership so callers can retry.
abstract interface class SpeechRecognizer {
  /// Loads [bundle], replacing any previously loaded ASR model.
  Future<AppResult<void>> loadModel(VerifiedAsrModelBundle bundle);

  /// Starts one live microphone recognition handle.
  Future<AppResult<SpeechRecognitionHandle>> start();

  /// Stops active recognition and releases the loaded model.
  Future<AppResult<void>> unload();

  /// Permanently releases capture, native model, and worker resources.
  Future<AppResult<void>> close();
}
