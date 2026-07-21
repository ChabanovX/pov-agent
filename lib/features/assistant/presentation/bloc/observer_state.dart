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

  /// A wake-phrase question submitted by the hands-free session.
  voice,
}

/// The foreground hands-free agent's user-visible phase.
enum VoiceAgentPhase {
  /// ASR has not started or cannot currently accept foreground work.
  unavailable,

  /// The verified ASR bundle or native recognizer is being prepared.
  preparing,

  /// Recognition is armed and waiting for the configured wake phrase.
  watching,

  /// One wake phrase was accepted for the current voice turn.
  wakeDetected,

  /// The agent is collecting the question until endpoint or deadline.
  listening,

  /// Qwen is generating the answer with the current scene and history.
  thinking,

  /// The committed voice answer is spoken while recognition stays paused.
  speaking,

  /// A recoverable permission, input, recognition, or empty-turn failure.
  failure,

  /// Lifecycle suspension has released foreground recognition resources.
  suspended,
}

/// The observer's model, scene, timer, transcript, generation, and speech state.
///
/// Automatic comments and user dialogue are stored separately so a previous
/// scene comment cannot accidentally count as one of the four dialogue pairs.
/// Drafts are never committed: cancellation can discard them without leaking
/// incomplete output into subsequent Qwen context. Speech targets only an
/// append-only committed comment index, so streaming output is never audible.
final class ObserverState {
  /// Creates the idle observer state.
  ObserverState({
    required this.wakePhrase,
    this.started = false,
    this.foregroundActive = true,
    this.observationEnabled = false,
    this.interval = ObserverInterval.tenSeconds,
    this.scene = const SceneSnapshot.empty(),
    this.modelStatus = ObserverModelStatus.idle,
    this.activeGeneration,
    this.speechMuted = false,
    this.activeSpeechCommentIndex,
    this.activeVoiceSpeechTurnId,
    this.asrModelStatus = ObserverModelStatus.idle,
    this.voicePhase = VoiceAgentPhase.unavailable,
    this.voiceTurnId,
    List<ObserverComment> comments = const [],
    List<ConversationMessage> messages = const [],
    this.modelDownloadProgress,
    this.asrModelDownloadProgress,
    this.manualDraftPrompt = '',
    this.manualDraftResponse = '',
    this.voiceQuestionDraft = '',
    this.voiceAnswerDraft = '',
    this.automaticDraft = '',
    this.modelFailure,
    this.asrModelFailure,
    this.manualFailure,
    this.voiceFailure,
    this.automaticFailure,
    this.speechFailure,
  }) : comments = List.unmodifiable(comments),
       messages = List.unmodifiable(messages);

  /// Configured phrase displayed while recognition waits for a voice turn.
  final String wakePhrase;

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

  /// Whether automatic comment speech is disabled for this runtime session.
  final bool speechMuted;

  /// Append-only index of the comment currently being spoken.
  final int? activeSpeechCommentIndex;

  /// Monotonic voice turn whose answer is currently being spoken.
  final int? activeVoiceSpeechTurnId;

  /// The verified streaming-ASR model preparation phase.
  final ObserverModelStatus asrModelStatus;

  /// The current hands-free interaction phase.
  final VoiceAgentPhase voicePhase;

  /// Monotonic active voice turn used to reject stale callbacks.
  final int? voiceTurnId;

  /// Completed automatic comments in session order.
  final List<ObserverComment> comments;

  /// Completed typed and hands-free dialogue in user/assistant order.
  final List<ConversationMessage> messages;

  /// Normalized download completion while [modelStatus] is downloading.
  final double? modelDownloadProgress;

  /// Normalized ASR download completion while its model is downloading.
  final double? asrModelDownloadProgress;

  /// The uncommitted manual prompt for an active or failed answer.
  final String manualDraftPrompt;

  /// The visible, uncommitted manual response prefix.
  final String manualDraftResponse;

  /// Normalized question collected for the active voice turn.
  final String voiceQuestionDraft;

  /// Visible, uncommitted Qwen response for the active voice turn.
  final String voiceAnswerDraft;

  /// The visible prefix of the active automatic comment.
  final String automaticDraft;

  /// The latest model preparation failure.
  final AppFailure? modelFailure;

  /// The latest verified-ASR preparation or native-load failure.
  final AppFailure? asrModelFailure;

  /// The latest manual-generation failure.
  final AppFailure? manualFailure;

  /// The latest recoverable hands-free interaction failure.
  final AppFailure? voiceFailure;

  /// The latest automatic-generation failure.
  final AppFailure? automaticFailure;

  /// The latest recoverable speech start, playback, or stop failure.
  final AppFailure? speechFailure;

  /// Whether either automatic or manual generation owns the runner.
  bool get isGenerating => activeGeneration != null;

  /// Whether one committed automatic comment or voice answer owns speech.
  bool get isSpeaking {
    return activeSpeechCommentIndex != null || activeVoiceSpeechTurnId != null;
  }

  /// The latest successfully committed automatic comment.
  String? get previousComment => comments.isEmpty ? null : comments.last.text;

  /// Whether a new manual request can start or preempt automatic generation.
  bool get canSubmit {
    return foregroundActive &&
        modelStatus == ObserverModelStatus.ready &&
        activeGeneration != ObserverGenerationKind.manual &&
        activeGeneration != ObserverGenerationKind.voice;
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
    String? wakePhrase,
    bool? started,
    bool? foregroundActive,
    bool? observationEnabled,
    ObserverInterval? interval,
    SceneSnapshot? scene,
    ObserverModelStatus? modelStatus,
    ObserverGenerationKind? Function()? activeGeneration,
    bool? speechMuted,
    int? Function()? activeSpeechCommentIndex,
    int? Function()? activeVoiceSpeechTurnId,
    ObserverModelStatus? asrModelStatus,
    VoiceAgentPhase? voicePhase,
    int? Function()? voiceTurnId,
    List<ObserverComment>? comments,
    List<ConversationMessage>? messages,
    double? Function()? modelDownloadProgress,
    double? Function()? asrModelDownloadProgress,
    String? manualDraftPrompt,
    String? manualDraftResponse,
    String? voiceQuestionDraft,
    String? voiceAnswerDraft,
    String? automaticDraft,
    AppFailure? Function()? modelFailure,
    AppFailure? Function()? asrModelFailure,
    AppFailure? Function()? manualFailure,
    AppFailure? Function()? voiceFailure,
    AppFailure? Function()? automaticFailure,
    AppFailure? Function()? speechFailure,
  }) {
    return ObserverState(
      wakePhrase: wakePhrase ?? this.wakePhrase,
      started: started ?? this.started,
      foregroundActive: foregroundActive ?? this.foregroundActive,
      observationEnabled: observationEnabled ?? this.observationEnabled,
      interval: interval ?? this.interval,
      scene: scene ?? this.scene,
      modelStatus: modelStatus ?? this.modelStatus,
      activeGeneration: activeGeneration == null ? this.activeGeneration : activeGeneration(),
      speechMuted: speechMuted ?? this.speechMuted,
      activeSpeechCommentIndex: activeSpeechCommentIndex == null
          ? this.activeSpeechCommentIndex
          : activeSpeechCommentIndex(),
      activeVoiceSpeechTurnId: activeVoiceSpeechTurnId == null
          ? this.activeVoiceSpeechTurnId
          : activeVoiceSpeechTurnId(),
      asrModelStatus: asrModelStatus ?? this.asrModelStatus,
      voicePhase: voicePhase ?? this.voicePhase,
      voiceTurnId: voiceTurnId == null ? this.voiceTurnId : voiceTurnId(),
      comments: comments ?? this.comments,
      messages: messages ?? this.messages,
      modelDownloadProgress: modelDownloadProgress == null ? this.modelDownloadProgress : modelDownloadProgress(),
      asrModelDownloadProgress: asrModelDownloadProgress == null
          ? this.asrModelDownloadProgress
          : asrModelDownloadProgress(),
      manualDraftPrompt: manualDraftPrompt ?? this.manualDraftPrompt,
      manualDraftResponse: manualDraftResponse ?? this.manualDraftResponse,
      voiceQuestionDraft: voiceQuestionDraft ?? this.voiceQuestionDraft,
      voiceAnswerDraft: voiceAnswerDraft ?? this.voiceAnswerDraft,
      automaticDraft: automaticDraft ?? this.automaticDraft,
      modelFailure: modelFailure == null ? this.modelFailure : modelFailure(),
      asrModelFailure: asrModelFailure == null ? this.asrModelFailure : asrModelFailure(),
      manualFailure: manualFailure == null ? this.manualFailure : manualFailure(),
      voiceFailure: voiceFailure == null ? this.voiceFailure : voiceFailure(),
      automaticFailure: automaticFailure == null ? this.automaticFailure : automaticFailure(),
      speechFailure: speechFailure == null ? this.speechFailure : speechFailure(),
    );
  }
}
