import 'package:pov_agent/features/assistant/application/models/generation_options.dart';

/// A fully formatted prompt and its bounded generation policy.
final class CommentGenerationRequest {
  /// Creates a request from a non-empty model [prompt].
  factory CommentGenerationRequest({
    required String prompt,
    required GenerationOptions options,
    bool startsInsideReasoning = false,
  }) {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(
        prompt,
        'prompt',
        'A generation prompt must not be empty.',
      );
    }
    return CommentGenerationRequest._(
      prompt: prompt,
      options: options,
      startsInsideReasoning: startsInsideReasoning,
    );
  }

  const CommentGenerationRequest._({
    required this.prompt,
    required this.options,
    required this.startsInsideReasoning,
  });

  /// The Qwen ChatML text passed to the tokenizer.
  final String prompt;

  /// Sampling and output limits for this request.
  final GenerationOptions options;

  /// Whether the prompt prefilled an opening `<think>` block.
  ///
  /// In this mode generated chunks begin with reasoning content and eventually
  /// emit only the closing tag. Streaming filters must suppress output from
  /// the first chunk instead of waiting to observe an opening tag.
  final bool startsInsideReasoning;
}
