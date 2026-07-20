import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_reasoning_filter.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';

const _chatStart = '<|im_start|>';
const _chatEnd = '<|im_end|>';
const _endOfText = '<|endoftext|>';
const _shortCommentSystemInstruction =
    'For this request, output only one brief complete English sentence of at '
    'least three words. '
    'Do not introduce or explain it.';

/// Formats assistant requests with Qwen3's pinned ChatML conversation shape.
///
/// The caller injects product copy and generation policies. This service owns
/// only Qwen control tokens, role formatting, soft thinking switches, and
/// defensive removal of reasoning and role-injection tokens from history.
final class QwenPromptBuilder {
  /// Creates a builder with explicit prompt copy and policies.
  QwenPromptBuilder({
    required String systemPrompt,
    required this.manualOptions,
    required this.shortCommentOptions,
  }) : _systemPrompt = _requirePrompt(systemPrompt, 'systemPrompt'),
       assert(
         manualOptions.maxTokens > 0,
         'manualOptions must permit generation.',
       ),
       assert(
         shortCommentOptions.maxTokens > 0,
         'shortCommentOptions must permit generation.',
       );

  final String _systemPrompt;

  /// The injected sampling and output policy for manual dialogue.
  final GenerationOptions manualOptions;

  /// The injected sampling and output policy for short comments.
  final GenerationOptions shortCommentOptions;

  /// Builds a `/think` request for manual dialogue.
  CommentGenerationRequest manualDialogue({
    required String prompt,
    List<ConversationMessage> history = const [],
  }) {
    return _build(
      prompt: prompt,
      history: history,
      thinkingSwitch: '/think',
      options: manualOptions,
      prefillReasoning: true,
      completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
    );
  }

  /// Builds a `/no_think` request for a bounded short comment.
  CommentGenerationRequest shortComment({
    required String prompt,
    List<ConversationMessage> history = const [],
  }) {
    return _build(
      prompt: prompt,
      history: history,
      thinkingSwitch: '/no_think',
      options: shortCommentOptions,
      prefillReasoning: false,
      systemInstruction: _shortCommentSystemInstruction,
      completionPolicy: GenerationCompletionPolicy.firstSubstantiveEnglishSentence,
    );
  }

  CommentGenerationRequest _build({
    required String prompt,
    required List<ConversationMessage> history,
    required String thinkingSwitch,
    required GenerationOptions options,
    required bool prefillReasoning,
    required GenerationCompletionPolicy completionPolicy,
    String? systemInstruction,
  }) {
    final sanitizedPrompt = _requirePrompt(prompt, 'prompt');
    final buffer = StringBuffer()
      ..write('${_chatStart}system\n')
      ..write(_systemPrompt);
    if (systemInstruction != null) {
      buffer
        ..write('\n')
        ..write(systemInstruction);
    }
    buffer.write('$_chatEnd\n');

    for (final message in history) {
      final content = _sanitizeHistoryMessage(message);
      if (content.isEmpty) continue;
      buffer
        ..write('$_chatStart${message.role.name}\n')
        ..write(content)
        ..write('$_chatEnd\n');
    }

    buffer
      ..write('${_chatStart}user\n')
      ..write(sanitizedPrompt)
      ..write('\n$thinkingSwitch$_chatEnd\n')
      ..write('${_chatStart}assistant\n');
    if (prefillReasoning) buffer.write('<think>\n');

    return CommentGenerationRequest(
      prompt: buffer.toString(),
      options: options,
      startsInsideReasoning: prefillReasoning,
      completionPolicy: completionPolicy,
    );
  }
}

String _sanitizeHistoryMessage(ConversationMessage message) {
  final visibleContent = switch (message.role) {
    ConversationRole.user => message.content,
    ConversationRole.assistant => QwenReasoningFilter.filterComplete(
      message.content,
    ),
  };
  return _sanitizeChatContent(visibleContent);
}

String _requirePrompt(String prompt, String argumentName) {
  final sanitized = _sanitizeChatContent(prompt);
  if (sanitized.isEmpty) {
    throw ArgumentError.value(
      prompt,
      argumentName,
      'Prompt content must not be empty.',
    );
  }
  return sanitized;
}

String _sanitizeChatContent(String content) {
  return content
      .replaceAll('\u0000', '')
      .replaceAll(_chatStart, ' ')
      .replaceAll(_chatEnd, ' ')
      .replaceAll(_endOfText, ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}
