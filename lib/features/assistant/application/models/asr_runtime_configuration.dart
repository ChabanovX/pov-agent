import 'package:meta/meta.dart';

/// Native streaming-ASR execution, decoding, and endpoint policy.
///
/// The values are prevalidated by app composition before they reach the data
/// adapter. Durations describe recognizer stream time, while presentation may
/// still impose a stricter wall-clock deadline around a listening session.
@immutable
final class AsrRuntimeConfiguration {
  /// Creates a prevalidated streaming-ASR runtime policy.
  const AsrRuntimeConfiguration({
    required this.provider,
    required this.threadCount,
    required this.sampleRateHz,
    required this.featureDimension,
    required this.decodingMethod,
    required this.maxActivePaths,
    required this.rule1MinTrailingSilence,
    required this.rule2MinTrailingSilence,
    required this.maxUtteranceDuration,
    required this.debug,
    required this.maxPendingAudioChunks,
  }) : assert(provider != '', 'provider must not be empty.'),
       assert(threadCount > 0, 'threadCount must be positive.'),
       assert(sampleRateHz > 0, 'sampleRateHz must be positive.'),
       assert(featureDimension > 0, 'featureDimension must be positive.'),
       assert(decodingMethod != '', 'decodingMethod must not be empty.'),
       assert(maxActivePaths > 0, 'maxActivePaths must be positive.'),
       assert(
         maxPendingAudioChunks > 0,
         'maxPendingAudioChunks must be positive.',
       );

  /// sherpa-onnx execution provider, such as `cpu`.
  final String provider;

  /// CPU thread count used by the online recognizer.
  final int threadCount;

  /// Requested microphone and feature-extractor sample rate.
  final int sampleRateHz;

  /// Filterbank feature dimension expected by the model.
  final int featureDimension;

  /// sherpa-onnx online decoding method.
  final String decodingMethod;

  /// Maximum active paths used by non-greedy decoders.
  final int maxActivePaths;

  /// Trailing silence for endpoint rule 1 when no non-blank token was decoded.
  final Duration rule1MinTrailingSilence;

  /// Trailing silence for endpoint rule 2 after non-blank tokens were decoded.
  final Duration rule2MinTrailingSilence;

  /// Maximum audio duration accepted for one recognizer segment.
  final Duration maxUtteranceDuration;

  /// Whether sherpa-onnx emits native diagnostics.
  final bool debug;

  /// Maximum unacknowledged microphone chunks queued for native decoding.
  ///
  /// Crossing this bound fails the active handle instead of allowing an
  /// unbounded isolate queue to retain raw audio in memory.
  final int maxPendingAudioChunks;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AsrRuntimeConfiguration &&
            provider == other.provider &&
            threadCount == other.threadCount &&
            sampleRateHz == other.sampleRateHz &&
            featureDimension == other.featureDimension &&
            decodingMethod == other.decodingMethod &&
            maxActivePaths == other.maxActivePaths &&
            rule1MinTrailingSilence == other.rule1MinTrailingSilence &&
            rule2MinTrailingSilence == other.rule2MinTrailingSilence &&
            maxUtteranceDuration == other.maxUtteranceDuration &&
            debug == other.debug &&
            maxPendingAudioChunks == other.maxPendingAudioChunks;
  }

  @override
  int get hashCode => Object.hash(
    provider,
    threadCount,
    sampleRateHz,
    featureDimension,
    decodingMethod,
    maxActivePaths,
    rule1MinTrailingSilence,
    rule2MinTrailingSilence,
    maxUtteranceDuration,
    debug,
    maxPendingAudioChunks,
  );
}
