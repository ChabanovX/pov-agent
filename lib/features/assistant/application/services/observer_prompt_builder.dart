import 'package:pov_agent/features/assistant/application/models/observer_prompt.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

const _dialoguePairLimit = 4;
const _historyMessageCharacterLimit = 220;
const _sceneObjectLimit = 24;
const _objectLabelCharacterLimit = 48;
const _previousCommentCharacterLimit = 320;

/// Builds bounded natural-language context from stable observer state.
///
/// Full session transcripts remain in presentation state. This builder limits
/// only model input so four manual pairs, scene details, and generation output
/// fit the pinned 2,048-token context conservatively.
final class ObserverPromptBuilder {
  /// Creates the stateless observer prompt builder.
  const ObserverPromptBuilder();

  /// Builds an automatic-comment prompt from the latest stable [scene].
  ObserverPrompt automaticComment({
    required SceneSnapshot scene,
    required List<ConversationMessage> dialogue,
    String? previousComment,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'Make one natural observation about this scene. Interpret it if '
        'useful, but invent no objects.',
      )
      ..writeln()
      ..writeln('Scene:')
      ..writeln(_formatScene(scene));

    final normalizedPrevious = previousComment?.trim();
    if (normalizedPrevious != null && normalizedPrevious.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Previous: '
          '${_truncate(normalizedPrevious, _previousCommentCharacterLimit)}',
        )
        ..writeln('Avoid repetition.');
    }

    return ObserverPrompt(
      text: buffer.toString().trim(),
      dialogueHistory: _boundedDialoguePairs(dialogue),
    );
  }

  /// Adds scene context and bounded dialogue history to a manual [prompt].
  ObserverPrompt manualDialogue({
    required String prompt,
    required SceneSnapshot scene,
    required List<ConversationMessage> dialogue,
    String? previousComment,
  }) {
    final buffer = StringBuffer()
      ..writeln('Current stable camera scene:')
      ..writeln(_formatScene(scene));
    final normalizedPrevious = previousComment?.trim();
    if (normalizedPrevious != null && normalizedPrevious.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Latest automatic observation: '
          '${_truncate(normalizedPrevious, _previousCommentCharacterLimit)}',
        );
    }
    buffer
      ..writeln()
      ..writeln('User message:')
      ..write(prompt.trim());
    return ObserverPrompt(
      text: buffer.toString(),
      dialogueHistory: _boundedDialoguePairs(dialogue),
    );
  }
}

String _formatScene(SceneSnapshot scene) {
  if (scene.isEmpty) return '- No stable objects are currently visible.';

  final visibleObjects = scene.objects.take(_sceneObjectLimit).toList(growable: false);
  final objectsByRegion = <SceneRegion, List<String>>{};
  for (final object in visibleObjects) {
    final label = _truncate(object.label.trim(), _objectLabelCharacterLimit);
    (objectsByRegion[object.region] ??= []).add(label);
  }
  final lines = objectsByRegion.entries
      .map((entry) => '- ${_regionLabel(entry.key)}: ${entry.value.join(', ')}')
      .toList();
  final omitted = scene.objects.length - visibleObjects.length;
  if (omitted > 0) lines.add('- $omitted additional stable objects omitted');
  return lines.join('\n');
}

List<ConversationMessage> _boundedDialoguePairs(
  List<ConversationMessage> dialogue,
) {
  final completeMessageCount = dialogue.length - dialogue.length.remainder(2);
  final firstMessage = completeMessageCount > _dialoguePairLimit * 2
      ? completeMessageCount - _dialoguePairLimit * 2
      : 0;
  final bounded = <ConversationMessage>[];
  for (var index = firstMessage; index < completeMessageCount; index += 1) {
    final message = dialogue[index];
    final content = _truncate(
      message.content.trim(),
      _historyMessageCharacterLimit,
    );
    if (content.isEmpty) continue;
    bounded.add(switch (message.role) {
      ConversationRole.user => ConversationMessage.user(content),
      ConversationRole.assistant => ConversationMessage.assistant(content),
    });
  }
  return List.unmodifiable(bounded);
}

String _regionLabel(SceneRegion region) {
  return switch (region) {
    SceneRegion.leftTop => 'upper left',
    SceneRegion.top => 'upper center',
    SceneRegion.rightTop => 'upper right',
    SceneRegion.left => 'middle left',
    SceneRegion.center => 'center',
    SceneRegion.right => 'middle right',
    SceneRegion.leftBottom => 'lower left',
    SceneRegion.bottom => 'lower center',
    SceneRegion.rightBottom => 'lower right',
  };
}

String _truncate(String value, int limit) {
  if (value.length <= limit) return value;
  return '${value.substring(0, limit - 1).trimRight()}…';
}
