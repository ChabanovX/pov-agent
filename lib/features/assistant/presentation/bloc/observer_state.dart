import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_comment.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

/// The local observer model's foreground preparation phase.
enum ObserverModelStatus {
  /// The process-owned observer has not started yet.
  idle,

  /// The cache is being resolved or the verified model is loading.
  loading,

  /// Model bytes are downloading into an incomplete staging file.
  downloading,

  /// Cached or downloaded bytes are being checked against the manifest.
  verifying,

  /// The verified model is loaded and accepts generation requests.
  ready,

  /// Model preparation failed and can be retried.
  failure,

  /// Foreground model work is paused by application lifecycle.
  suspended,
}

/// The origin of the one generation that may be active at a time.
enum ObserverGenerationKind {
  /// A timer-driven short scene comment.
  automatic,

  /// A user-submitted free-form dialogue answer.
  manual,
}

/// The observer's model, scene, timer, transcript, and generation projection.
///
/// Automatic comments and manual dialogue are stored separately so a previous
/// scene comment cannot accidentally count as one of the four dialogue pairs.
/// Drafts are never committed: cancellation can discard them without leaking
/// incomplete output into subsequent Qwen context.
final class ObserverState {
  /// Creates the idle observer state.
  ObserverState({
    this.started = false,
    this.foregroundActive = true,
    this.observationEnabled = false,
    this.interval = ObserverInterval.tenSeconds,
    this.scene = const SceneSnapshot.empty(),
    this.modelStatus = ObserverModelStatus.idle,
    this.activeGeneration,
    List<ObserverComment> comments = const [],
    List<ConversationMessage> messages = const [],
    this.modelDownloadProgress,
    this.manualDraftPrompt = '',
    this.manualDraftResponse = '',
    this.automaticDraft = '',
    this.modelFailure,
    this.manualFailure,
    this.automaticFailure,
  }) : comments = List.unmodifiable(comments),
       messages = List.unmodifiable(messages);

  /// Whether process startup has activated this observer session.
  final bool started;

  /// Whether foreground work currently accepts timer and manual requests.
  final bool foregroundActive;

  /// The session-only desired automatic-observation setting.
  final bool observationEnabled;

  /// The selected session-only automatic cadence.
  final ObserverInterval interval;

  /// The latest stable scene published for UI display.
  final SceneSnapshot scene;

  /// The current verified-model preparation phase.
  final ObserverModelStatus modelStatus;

  /// The active generation origin, or `null` while the runner is idle.
  final ObserverGenerationKind? activeGeneration;

  /// Completed automatic comments in session order.
  final List<ObserverComment> comments;

  /// Completed manual dialogue messages in user/assistant order.
  final List<ConversationMessage> messages;

  /// Normalized download completion while [modelStatus] is downloading.
  final double? modelDownloadProgress;

  /// The uncommitted manual prompt for an active or failed answer.
  final String manualDraftPrompt;

  /// The visible, uncommitted manual response prefix.
  final String manualDraftResponse;

  /// The visible prefix of the active automatic comment.
  final String automaticDraft;

  /// The latest model preparation failure.
  final AppFailure? modelFailure;

  /// The latest manual-generation failure.
  final AppFailure? manualFailure;

  /// The latest automatic-generation failure.
  final AppFailure? automaticFailure;

  /// Whether either automatic or manual generation owns the runner.
  bool get isGenerating => activeGeneration != null;

  /// The latest successfully committed automatic comment.
  String? get previousComment => comments.isEmpty ? null : comments.last.text;

  /// Whether a new manual request can start or preempt automatic generation.
  bool get canSubmit {
    return foregroundActive &&
        modelStatus == ObserverModelStatus.ready &&
        activeGeneration != ObserverGenerationKind.manual;
  }

  /// Whether the failed manual prompt can be resubmitted unchanged.
  bool get canRetryAnswer {
    return canSubmit && manualFailure != null && manualDraftPrompt.isNotEmpty;
  }

  /// A copy with selected state dimensions replaced.
  ///
  /// Nullable values use callbacks so callers can distinguish retaining a
  /// value from explicitly clearing it.
  ObserverState copyWith({
    bool? started,
    bool? foregroundActive,
    bool? observationEnabled,
    ObserverInterval? interval,
    SceneSnapshot? scene,
    ObserverModelStatus? modelStatus,
    ObserverGenerationKind? Function()? activeGeneration,
    List<ObserverComment>? comments,
    List<ConversationMessage>? messages,
    double? Function()? modelDownloadProgress,
    String? manualDraftPrompt,
    String? manualDraftResponse,
    String? automaticDraft,
    AppFailure? Function()? modelFailure,
    AppFailure? Function()? manualFailure,
    AppFailure? Function()? automaticFailure,
  }) {
    return ObserverState(
      started: started ?? this.started,
      foregroundActive: foregroundActive ?? this.foregroundActive,
      observationEnabled: observationEnabled ?? this.observationEnabled,
      interval: interval ?? this.interval,
      scene: scene ?? this.scene,
      modelStatus: modelStatus ?? this.modelStatus,
      activeGeneration: activeGeneration == null ? this.activeGeneration : activeGeneration(),
      comments: comments ?? this.comments,
      messages: messages ?? this.messages,
      modelDownloadProgress: modelDownloadProgress == null ? this.modelDownloadProgress : modelDownloadProgress(),
      manualDraftPrompt: manualDraftPrompt ?? this.manualDraftPrompt,
      manualDraftResponse: manualDraftResponse ?? this.manualDraftResponse,
      automaticDraft: automaticDraft ?? this.automaticDraft,
      modelFailure: modelFailure == null ? this.modelFailure : modelFailure(),
      manualFailure: manualFailure == null ? this.manualFailure : manualFailure(),
      automaticFailure: automaticFailure == null ? this.automaticFailure : automaticFailure(),
    );
  }
}
