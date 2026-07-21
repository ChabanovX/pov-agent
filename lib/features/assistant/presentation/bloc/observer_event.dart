part of 'observer_bloc.dart';

/// An input accepted by [ObserverBloc].
sealed class ObserverEvent {
  /// Defines a serializable observer intent or internal callback.
  const ObserverEvent();
}

/// Starts the process-owned foreground observer exactly once.
final class ObserverStarted extends ObserverEvent {
  /// Requests idempotent observer startup.
  const ObserverStarted();
}

/// Retries the latest model preparation failure.
final class ObserverModelRetryRequested extends ObserverEvent {
  /// Requests another model preparation attempt.
  const ObserverModelRetryRequested();
}

/// Enables periodic automatic comments for this runtime session.
final class ObservationStarted extends ObserverEvent {
  /// Enables the periodic observer for the current session.
  const ObservationStarted();
}

/// Stops periodic comments and cancels an active automatic generation.
final class ObservationStopped extends ObserverEvent {
  /// Disables the periodic observer for the current session.
  const ObservationStopped();
}

/// Replaces the session-only automatic comment [interval].
final class ObservationIntervalSelected extends ObserverEvent {
  /// Selects [interval] as the current session cadence.
  const ObservationIntervalSelected(this.interval);

  /// The selected supported cadence.
  final ObserverInterval interval;
}

/// Starts a manual `/think` dialogue turn for [prompt].
final class ObserverPromptSubmitted extends ObserverEvent {
  /// Submits [prompt] as a manual dialogue turn.
  const ObserverPromptSubmitted(this.prompt);

  /// The user-entered prompt.
  final String prompt;
}

/// Cooperatively cancels the active manual generation.
final class ObserverManualGenerationCancelled extends ObserverEvent {
  /// Cancels the uncommitted manual dialogue turn.
  const ObserverManualGenerationCancelled();
}

/// Resubmits the uncommitted prompt from the latest failed manual answer.
final class ObserverAnswerRetryRequested extends ObserverEvent {
  /// Retries the retained prompt from the latest failed turn.
  const ObserverAnswerRetryRequested();
}

/// Clears a recoverable hands-free failure and re-arms recognition.
final class ObserverVoiceRetryRequested extends ObserverEvent {
  /// Requests verified ASR preparation, permission, and capture again.
  const ObserverVoiceRetryRequested();
}

/// Changes the session-only hands-free microphone preference.
final class ObserverHandsFreeEnabledChanged extends ObserverEvent {
  /// Creates a hands-free preference intent.
  const ObserverHandsFreeEnabledChanged({required this.enabled});

  /// Whether wake-phrase recognition may run while Assistant is active.
  final bool enabled;
}

/// Opens platform application settings after microphone access is denied.
final class ObserverMicrophoneSettingsRequested extends ObserverEvent {
  /// Creates a microphone-permission recovery intent.
  const ObserverMicrophoneSettingsRequested();
}

/// Changes the session-only automatic speech mute preference.
final class ObserverSpeechMutedChanged extends ObserverEvent {
  /// Sets whether completed automatic comments may be spoken.
  const ObserverSpeechMutedChanged({required this.muted});

  /// Whether automatic speech is disabled for this runtime session.
  final bool muted;
}

/// Stops the active utterance without muting future automatic comments.
final class ObserverSpeechStopped extends ObserverEvent {
  /// Requests cooperative stop of the current utterance.
  const ObserverSpeechStopped();
}

/// Replays one committed automatic comment by append-only index.
final class ObserverCommentReplayRequested extends ObserverEvent {
  /// Requests speech for [commentIndex] when generation and speech are idle.
  const ObserverCommentReplayRequested(this.commentIndex);

  /// Index in the current session's append-only comment transcript.
  final int commentIndex;
}

/// Replays one committed Assistant dialogue response by append-only index.
final class ObserverMessageReplayRequested extends ObserverEvent {
  /// Requests speech for [messageIndex] when generation and speech are idle.
  const ObserverMessageReplayRequested(this.messageIndex);

  /// Index in the current session's append-only dialogue transcript.
  final int messageIndex;
}

/// Quiesces ticks and generation before camera foreground teardown.
final class ObserverForegroundDeactivated extends ObserverEvent {
  /// Begins the foreground quiescence handshake.
  const ObserverForegroundDeactivated();
}

/// Suspends model resources after the camera pipeline has settled.
final class ObserverSuspended extends ObserverEvent {
  /// Releases model resources after foreground work is quiescent.
  const ObserverSuspended();
}

/// Restores foreground work and reloads a previously suspended model.
final class ObserverResumed extends ObserverEvent {
  /// Restores observer work after foreground re-entry.
  const ObserverResumed();
}

final class _ObserverTicked extends ObserverEvent {
  const _ObserverTicked();
}

final class _SceneChanged extends ObserverEvent {
  const _SceneChanged(this.scene);

  final SceneSnapshot scene;
}

final class _ModelUpdateReceived extends ObserverEvent {
  const _ModelUpdateReceived(this.update);

  final ObserverModelUpdate update;
}

final class _GenerationUpdateReceived extends ObserverEvent {
  const _GenerationUpdateReceived(this.update);

  final ObserverGenerationUpdate update;
}

final class _SpeechUpdateReceived extends ObserverEvent {
  const _SpeechUpdateReceived(this.update);

  final ObserverSpeechCompleted update;
}

final class _VoiceInputUpdateReceived extends ObserverEvent {
  const _VoiceInputUpdateReceived(this.update);

  final ObserverVoiceInputUpdate update;
}
