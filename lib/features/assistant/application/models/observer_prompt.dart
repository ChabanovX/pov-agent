import 'package:meta/meta.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';

/// Structured semantic input for one automatic Qwen comment.
@immutable
final class ObserverPrompt {
  /// Creates an observer prompt with bounded dialogue context.
  ObserverPrompt({
    required this.text,
    required List<ConversationMessage> dialogueHistory,
  }) : dialogueHistory = List.unmodifiable(dialogueHistory);

  /// The current-scene and previous-comment instruction.
  final String text;

  /// Up to four completed, bounded manual dialogue pairs.
  final List<ConversationMessage> dialogueHistory;
}
