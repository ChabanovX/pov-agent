import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';

void main() {
  test('creates trimmed session-only user and assistant messages', () {
    final user = ConversationMessage.user('  Where am I?  ');
    final assistant = ConversationMessage.assistant('  You are inside.  ');

    expect(user.role, ConversationRole.user);
    expect(user.content, 'Where am I?');
    expect(assistant.role, ConversationRole.assistant);
    expect(assistant.content, 'You are inside.');
    expect(
      ConversationMessage.user('Where am I?'),
      user,
    );
  });

  test('rejects messages without visible content', () {
    expect(
      () => ConversationMessage.user(' \n\t '),
      throwsArgumentError,
    );
    expect(
      () => ConversationMessage.assistant(''),
      throwsArgumentError,
    );
  });
}
