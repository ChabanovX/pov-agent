import 'package:meta/meta.dart';

/// A role represented in the session-only assistant conversation.
enum ConversationRole {
  /// Text entered by the user.
  user,

  /// Visible answer text produced by the assistant.
  assistant,
}

/// One visible message retained for the current assistant session.
///
/// Messages have no persistence identity or serialization contract. Assistant
/// messages contain only user-visible answer text; model reasoning must be
/// removed before constructing them.
@immutable
final class ConversationMessage {
  /// Creates a user message from non-empty [content].
  factory ConversationMessage.user(String content) {
    return ConversationMessage._(
      role: ConversationRole.user,
      content: _requireContent(content),
    );
  }

  /// Creates an assistant message from non-empty visible [content].
  factory ConversationMessage.assistant(String content) {
    return ConversationMessage._(
      role: ConversationRole.assistant,
      content: _requireContent(content),
    );
  }

  const ConversationMessage._({
    required this.role,
    required this.content,
  });

  /// The participant that produced this message.
  final ConversationRole role;

  /// The trimmed, user-visible message text.
  final String content;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ConversationMessage && role == other.role && content == other.content;
  }

  @override
  int get hashCode => Object.hash(role, content);
}

String _requireContent(String content) {
  final normalized = content.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      content,
      'content',
      'Conversation content must not be empty.',
    );
  }
  return normalized;
}
