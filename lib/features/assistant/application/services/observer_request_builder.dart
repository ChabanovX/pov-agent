import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/services/observer_prompt_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

/// Converts observer context into the two supported Qwen request shapes.
///
/// Semantic scene formatting and Qwen control-token formatting remain separate
/// lower-level policies. This builder owns how those policies are combined and
/// how much completed manual history each generation mode receives.
final class ObserverRequestBuilder {
  /// Creates a request builder from the configured Qwen policy.
  factory ObserverRequestBuilder({
    required QwenPromptBuilder qwenPromptBuilder,
    ObserverPromptBuilder observerPromptBuilder = const ObserverPromptBuilder(),
  }) {
    return ObserverRequestBuilder._(
      qwenPromptBuilder,
      observerPromptBuilder,
    );
  }

  ObserverRequestBuilder._(
    this._qwenPromptBuilder,
    this._observerPromptBuilder,
  );

  final QwenPromptBuilder _qwenPromptBuilder;
  final ObserverPromptBuilder _observerPromptBuilder;

  /// Builds a scene observation with the bounded four-pair dialogue context.
  CommentGenerationRequest automatic({
    required SceneSnapshot scene,
    required List<ConversationMessage> dialogue,
    String? previousComment,
  }) {
    final prompt = _observerPromptBuilder.automaticComment(
      scene: scene,
      previousComment: previousComment,
      dialogue: dialogue,
    );
    return _qwenPromptBuilder.shortComment(
      prompt: prompt.text,
      history: prompt.dialogueHistory,
    );
  }

  /// Builds a manual request with the bounded four-pair dialogue context.
  CommentGenerationRequest manual({
    required String prompt,
    required SceneSnapshot scene,
    required List<ConversationMessage> dialogue,
    String? previousComment,
  }) {
    final contextualPrompt = _observerPromptBuilder.manualDialogue(
      prompt: prompt,
      scene: scene,
      dialogue: dialogue,
      previousComment: previousComment,
    );
    return _qwenPromptBuilder.manualDialogue(
      prompt: contextualPrompt.text,
      history: contextualPrompt.dialogueHistory,
    );
  }
}
