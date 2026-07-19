import 'package:meta/meta.dart';

/// Sampling and output limits for one local text generation.
@immutable
final class GenerationOptions {
  /// Creates validated generation options.
  const GenerationOptions({
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.minP,
  }) : assert(maxTokens > 0, 'maxTokens must be positive.'),
       assert(temperature > 0, 'temperature must be positive.'),
       assert(topP > 0 && topP <= 1, 'topP must be in the range (0, 1].'),
       assert(topK > 0, 'topK must be positive.'),
       assert(minP >= 0 && minP <= 1, 'minP must be in the range [0, 1].');

  /// Maximum number of tokens generated after the prompt.
  final int maxTokens;

  /// Sampling temperature applied to token logits.
  final double temperature;

  /// Nucleus-sampling probability threshold.
  final double topP;

  /// Maximum number of highest-probability token candidates sampled.
  final int topK;

  /// Relative-probability floor used to remove unlikely token candidates.
  final double minP;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GenerationOptions &&
            maxTokens == other.maxTokens &&
            temperature == other.temperature &&
            topP == other.topP &&
            topK == other.topK &&
            minP == other.minP;
  }

  @override
  int get hashCode => Object.hash(maxTokens, temperature, topP, topK, minP);
}
