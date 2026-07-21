import 'package:meta/meta.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// Why a streaming recognition segment reached its terminal boundary.
enum SpeechRecognitionEndpointReason {
  /// Native endpointing observed the configured trailing silence.
  trailingSilence,

  /// The segment reached the configured maximum audio duration.
  maximumDuration,
}

/// A tagged event emitted by one active speech-recognition handle.
///
/// [segmentId] changes after every explicit stream reset. [revision] is
/// monotonic for the lifetime of the handle, so presentation can discard a
/// stale event that crossed an asynchronous reset or stop boundary.
@immutable
sealed class SpeechRecognitionEvent {
  const SpeechRecognitionEvent({
    required this.segmentId,
    required this.revision,
  }) : assert(segmentId >= 0, 'segmentId must not be negative.'),
       assert(revision > 0, 'revision must be positive.');

  /// The zero-based segment within the active recognition handle.
  final int segmentId;

  /// The monotonically increasing event revision within the active handle.
  final int revision;
}

/// The current cumulative transcript for one recognition segment.
///
/// [transcript] replaces the previous hypothesis for the same [segmentId]; it
/// is never a token delta.
final class SpeechRecognitionHypothesis extends SpeechRecognitionEvent {
  /// Creates a cumulative hypothesis event.
  const SpeechRecognitionHypothesis({
    required super.segmentId,
    required super.revision,
    required this.transcript,
  });

  /// The cumulative transcript returned by the native recognizer.
  final String transcript;
}

/// The terminal boundary for one recognition segment.
final class SpeechRecognitionEndpoint extends SpeechRecognitionEvent {
  /// Creates an endpoint event with the final cumulative [transcript].
  const SpeechRecognitionEndpoint({
    required super.segmentId,
    required super.revision,
    required this.transcript,
    required this.reason,
  });

  /// The final cumulative transcript captured before native reset or stop.
  final String transcript;

  /// Why the segment ended.
  final SpeechRecognitionEndpointReason reason;
}

/// A normalized terminal failure for the active recognition handle.
final class SpeechRecognitionFailure extends SpeechRecognitionEvent {
  /// Creates a recognition failure event.
  const SpeechRecognitionFailure({
    required super.segmentId,
    required super.revision,
    required this.failure,
  });

  /// The failure safe to expose beyond the data boundary.
  final AppFailure failure;
}
