import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// The local assistant model's foreground preparation phase.
enum AssistantModelStatus {
  /// The assistant tab has not requested model preparation.
  idle,

  /// The cache is being resolved or the verified model is loading.
  loading,

  /// Model bytes are downloading into an incomplete staging file.
  downloading,

  /// Cached or downloaded bytes are being checked against the manifest.
  verifying,

  /// The verified model is loaded and accepts manual prompts.
  ready,

  /// Model preparation failed and can be retried.
  failure,

  /// Foreground model work is paused by application lifecycle.
  suspended,
}

/// The state of the single allowed manual generation.
enum AssistantGenerationStatus {
  /// No manual generation is active.
  idle,

  /// One answer is starting or streaming.
  generating,

  /// The last answer failed and its prompt can be retried.
  failure,
}

/// The assistant's model lifecycle, session transcript, and active draft.
///
/// One immutable value keeps the independently changing model and generation
/// phases coherent. [messages] contains only completed turns. The draft prompt
/// and response remain separate so cancellation can discard both without
/// leaking an incomplete turn into future Qwen history.
final class AssistantState {
  /// Creates the initial assistant state.
  AssistantState({
    this.started = false,
    this.modelStatus = AssistantModelStatus.idle,
    this.generationStatus = AssistantGenerationStatus.idle,
    List<ConversationMessage> messages = const [],
    this.modelDownloadProgress,
    this.draftPrompt = '',
    this.draftResponse = '',
    this.modelFailure,
    this.generationFailure,
  }) : messages = List.unmodifiable(messages);

  /// Whether the router has requested this process-owned assistant session.
  final bool started;

  /// The current verified-model preparation phase.
  final AssistantModelStatus modelStatus;

  /// The current manual-generation phase.
  final AssistantGenerationStatus generationStatus;

  /// Completed, session-only dialogue turns in display and prompt order.
  final List<ConversationMessage> messages;

  /// Normalized download completion while [modelStatus] is downloading.
  final double? modelDownloadProgress;

  /// The uncommitted user prompt for an active or failed answer.
  final String draftPrompt;

  /// The visible, uncommitted response prefix received so far.
  final String draftResponse;

  /// The latest model preparation failure.
  final AppFailure? modelFailure;

  /// The latest manual-generation failure.
  final AppFailure? generationFailure;

  /// Whether the model currently accepts a new manual request.
  bool get canSubmit {
    return modelStatus == AssistantModelStatus.ready && generationStatus != AssistantGenerationStatus.generating;
  }

  /// Whether the failed draft prompt can be resubmitted unchanged.
  bool get canRetryAnswer {
    return modelStatus == AssistantModelStatus.ready &&
        generationStatus == AssistantGenerationStatus.failure &&
        draftPrompt.isNotEmpty;
  }

  /// A copy with selected state dimensions replaced.
  ///
  /// Nullable values use callbacks so callers can distinguish retaining a
  /// value from explicitly clearing it.
  AssistantState copyWith({
    bool? started,
    AssistantModelStatus? modelStatus,
    AssistantGenerationStatus? generationStatus,
    List<ConversationMessage>? messages,
    double? Function()? modelDownloadProgress,
    String? draftPrompt,
    String? draftResponse,
    AppFailure? Function()? modelFailure,
    AppFailure? Function()? generationFailure,
  }) {
    return AssistantState(
      started: started ?? this.started,
      modelStatus: modelStatus ?? this.modelStatus,
      generationStatus: generationStatus ?? this.generationStatus,
      messages: messages ?? this.messages,
      modelDownloadProgress: modelDownloadProgress == null ? this.modelDownloadProgress : modelDownloadProgress(),
      draftPrompt: draftPrompt ?? this.draftPrompt,
      draftResponse: draftResponse ?? this.draftResponse,
      modelFailure: modelFailure == null ? this.modelFailure : modelFailure(),
      generationFailure: generationFailure == null ? this.generationFailure : generationFailure(),
    );
  }
}
