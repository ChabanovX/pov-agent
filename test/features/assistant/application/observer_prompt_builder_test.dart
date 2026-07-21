import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/services/observer_prompt_builder.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/tracked_object.dart';

void main() {
  const builder = ObserverPromptBuilder();

  test('describes an empty stable scene explicitly', () {
    final prompt = builder.automaticComment(
      scene: const SceneSnapshot.empty(),
      dialogue: const [],
    );

    expect(prompt.text, contains('No stable objects are currently visible'));
    expect(prompt.text, isNot(contains('Previous:')));
    expect(prompt.dialogueHistory, isEmpty);
  });

  test('formats canonical objects and the previous completed comment', () {
    final prompt = builder.automaticComment(
      scene: SceneSnapshot(
        objects: const [
          TrackedObject(
            id: 8,
            classId: 24,
            label: 'backpack',
            region: SceneRegion.rightBottom,
          ),
          TrackedObject(
            id: 2,
            classId: 0,
            label: 'person',
            region: SceneRegion.center,
          ),
        ],
      ),
      previousComment: 'Someone is standing in the room.',
      dialogue: const [],
    );

    expect(
      prompt.text,
      contains('- center: person\n- lower right: backpack'),
    );
    expect(
      prompt.text,
      contains('Previous: Someone is standing in the room.'),
    );
    expect(prompt.text, contains('Avoid repetition.'));
  });

  test('groups labels by region and reports objects beyond the prompt bound', () {
    final prompt = builder.automaticComment(
      scene: SceneSnapshot(
        objects: [
          for (var id = 1; id <= 26; id += 1)
            TrackedObject(
              id: id,
              classId: id,
              label: 'object$id',
              region: SceneRegion.leftTop,
            ),
        ],
      ),
      dialogue: const [],
    );

    expect(prompt.text, contains('- upper left: object1, object2'));
    expect(prompt.text, contains('object24'));
    expect(prompt.text, isNot(contains('object25')));
    expect(prompt.text, contains('- 2 additional stable objects omitted'));
    expect(prompt.text, isNot(contains('#1')));
  });

  test('retains only the newest four complete bounded dialogue pairs', () {
    final dialogue = <ConversationMessage>[];
    for (var pair = 1; pair <= 5; pair += 1) {
      dialogue
        ..add(ConversationMessage.user('question $pair ${'u' * 300}'))
        ..add(ConversationMessage.assistant('answer $pair ${'a' * 300}'));
    }
    // An unmatched draft-like message is not a completed pair.
    dialogue.add(ConversationMessage.user('unmatched draft'));

    final prompt = builder.automaticComment(
      scene: const SceneSnapshot.empty(),
      dialogue: dialogue,
    );

    expect(prompt.dialogueHistory, hasLength(8));
    expect(prompt.dialogueHistory.first.content, startsWith('question 2'));
    expect(prompt.dialogueHistory.last.content, startsWith('answer 5'));
    expect(
      prompt.dialogueHistory.every((message) => message.content.length <= 220),
      isTrue,
    );
    expect(
      prompt.dialogueHistory.any(
        (message) => message.content.contains('unmatched draft'),
      ),
      isFalse,
    );
  });

  test('manual prompt includes current scene and latest observer comment', () {
    final prompt = builder.manualDialogue(
      prompt: 'What is happening?',
      scene: SceneSnapshot(
        objects: const [
          TrackedObject(
            id: 1,
            classId: 0,
            label: 'person',
            region: SceneRegion.left,
          ),
        ],
      ),
      dialogue: const [],
      previousComment: 'A person has entered the frame.',
    );

    expect(prompt.text, contains('- middle left: person'));
    expect(prompt.text, contains('A person has entered the frame.'));
    expect(prompt.text, endsWith('What is happening?'));
    expect(prompt.dialogueHistory, isEmpty);
  });
}
