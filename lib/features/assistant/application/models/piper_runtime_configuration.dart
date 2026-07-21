import 'package:meta/meta.dart';

/// sherpa-onnx execution and decoding policy for one Piper utterance.
@immutable
final class PiperRuntimeConfiguration {
  /// Creates a prevalidated Piper runtime policy.
  const PiperRuntimeConfiguration({
    required this.provider,
    required this.threadCount,
    required this.speakerId,
    required this.noiseScale,
    required this.noiseScaleW,
    required this.lengthScale,
    required this.speed,
    required this.silenceScale,
    required this.maxSentences,
    required this.debug,
  }) : assert(provider != '', 'provider must not be empty.'),
       assert(threadCount > 0, 'threadCount must be positive.'),
       assert(speakerId >= 0, 'speakerId must not be negative.'),
       assert(noiseScale >= 0, 'noiseScale must not be negative.'),
       assert(noiseScaleW >= 0, 'noiseScaleW must not be negative.'),
       assert(lengthScale > 0, 'lengthScale must be positive.'),
       assert(speed > 0, 'speed must be positive.'),
       assert(silenceScale >= 0, 'silenceScale must not be negative.'),
       assert(maxSentences > 0, 'maxSentences must be positive.');

  /// sherpa-onnx execution provider name.
  final String provider;

  /// CPU thread count used during synthesis.
  final int threadCount;

  /// Speaker index passed to the selected voice model.
  final int speakerId;

  /// VITS stochastic noise applied to the generated waveform.
  final double noiseScale;

  /// VITS stochastic noise applied to phoneme durations.
  final double noiseScaleW;

  /// VITS duration multiplier configured while loading the model.
  final double lengthScale;

  /// Speech-rate multiplier passed to the generator.
  final double speed;

  /// Generated-silence scale passed to the generator.
  final double silenceScale;

  /// Maximum number of sentence chunks synthesized by one native request.
  final int maxSentences;

  /// Whether sherpa-onnx emits native diagnostic logs.
  final bool debug;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PiperRuntimeConfiguration &&
            provider == other.provider &&
            threadCount == other.threadCount &&
            speakerId == other.speakerId &&
            noiseScale == other.noiseScale &&
            noiseScaleW == other.noiseScaleW &&
            lengthScale == other.lengthScale &&
            speed == other.speed &&
            silenceScale == other.silenceScale &&
            maxSentences == other.maxSentences &&
            debug == other.debug;
  }

  @override
  int get hashCode {
    return Object.hash(
      provider,
      threadCount,
      speakerId,
      noiseScale,
      noiseScaleW,
      lengthScale,
      speed,
      silenceScale,
      maxSentences,
      debug,
    );
  }
}
