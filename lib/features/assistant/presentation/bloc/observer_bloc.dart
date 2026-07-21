import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/wake_phrase_detector.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_comment.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_generation_session.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_model_session.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_speech_session.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_speech_target.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_timer_controller.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_voice_input_session.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

part 'observer_event.dart';
part 'observer_generation_policy.dart';
part 'observer_dependencies.dart';
part 'observer_lifecycle_policy.dart';
part 'observer_speech_policy.dart';
part 'observer_voice_policy.dart';

/// Owns the continuous foreground observer projected by [ObserverState].
///
/// One ordered event queue arbitrates timer ticks, manual requests, lifecycle,
/// scene changes, and native callbacks. Automatic ticks use `ignore`: they read
/// [SceneSource.current] when handled and are discarded whenever the shared
/// generation runner is busy. Manual requests may preempt automatic work.
///
/// Completed automatic comments may start one single-flight speech session.
/// Speech never queues: ticks are ignored while generation or speech owns its
/// slot, while manual requests preempt both automatic generation and speech.
///
/// The Bloc owns the scene subscription and its timer, model, generation,
/// speech, and voice-input sessions, but not the injected ports. [close]
/// quiesces every owned producer before process composition closes those
/// app-owned resources.
final class ObserverBloc extends Bloc<ObserverEvent, ObserverState> {
  /// Creates an idle observer without starting model or timer work.
  factory ObserverBloc({
    required ObserverGenerationDependencies generation,
    required ObserverVoiceDependencies voice,
    ObserverPeriodicTimerFactory? periodicTimerFactory,
    ObserverVoiceDeadlineFactory? voiceDeadlineFactory,
  }) {
    return ObserverBloc._(
      generation,
      voice,
      periodicTimerFactory,
      voiceDeadlineFactory,
    );
  }

  ObserverBloc._(
    ObserverGenerationDependencies generation,
    ObserverVoiceDependencies voice,
    ObserverPeriodicTimerFactory? periodicTimerFactory,
    ObserverVoiceDeadlineFactory? voiceDeadlineFactory,
  ) : _sceneSource = generation.sceneSource,
      _requestBuilder = generation.requestBuilder,
      super(ObserverState(wakePhrase: voice.wakePhrase)) {
    _modelSession = ObserverModelSession(
      modelStore: generation.qwenModelStore,
      onUpdate: _forwardModelUpdate,
    );
    _generationSession = ObserverGenerationSession(
      commentGenerator: generation.commentGenerator,
      onUpdate: _forwardGenerationUpdate,
    );
    _speechSession = ObserverSpeechSession(
      speechSynthesizer: voice.speechSynthesizer,
      onUpdate: _forwardSpeechUpdate,
    );
    _voiceInputSession = ObserverVoiceInputSession(
      modelStore: voice.asrModelStore,
      permissionGateway: voice.microphonePermissionGateway,
      speechRecognizer: voice.speechRecognizer,
      wakePhraseDetector: WakePhraseDetector(voice.wakePhrase),
      questionDeadline: voice.questionDeadline,
      onUpdate: _forwardVoiceInputUpdate,
      deadlineFactory: voiceDeadlineFactory,
    );
    _timerController = periodicTimerFactory == null
        ? ObserverTimerController(onTick: _forwardTimerTick)
        : ObserverTimerController(
            onTick: _forwardTimerTick,
            periodicTimerFactory: periodicTimerFactory,
          );
    // A single sequential family makes the runner slot and state projection
    // one atomic policy. Detached native work reports back as queued events.
    on<ObserverEvent>(_onEvent, transformer: sequential());
  }

  /// Maximum user-entered characters retained in one manual prompt.
  static const manualPromptCharacterLimit = 320;

  final SceneSource _sceneSource;
  final ObserverRequestBuilder _requestBuilder;
  late final ObserverModelSession _modelSession;
  late final ObserverGenerationSession _generationSession;
  late final ObserverSpeechSession _speechSession;
  late final ObserverVoiceInputSession _voiceInputSession;
  late final ObserverTimerController _timerController;

  StreamSubscription<SceneSnapshot>? _sceneSubscription;
  Future<void>? _closeTask;

  var _acceptsForegroundWork = true;
  var _closing = false;

  Future<void> _onEvent(
    ObserverEvent event,
    Emitter<ObserverState> emit,
  ) async {
    switch (event) {
      case ObserverStarted():
        _onStarted(emit);
      case ObserverModelRetryRequested():
        await _onModelRetryRequested(emit);
      case ObservationStarted():
        _onObservationStarted(emit);
      case ObservationStopped():
        await _onObservationStopped(emit);
      case ObservationIntervalSelected(:final interval):
        _onIntervalSelected(interval, emit);
      case ObserverPromptSubmitted(:final prompt):
        await _onPromptSubmitted(prompt, emit);
      case ObserverManualGenerationCancelled():
        await _onManualGenerationCancelled(emit);
      case ObserverAnswerRetryRequested():
        await _onAnswerRetryRequested(emit);
      case ObserverVoiceRetryRequested():
        await _onVoiceRetryRequested(emit);
      case ObserverSpeechMutedChanged(:final muted):
        await _onSpeechMutedChanged(muted, emit);
      case ObserverSpeechStopped():
        await _onSpeechStopped(emit);
      case ObserverCommentReplayRequested(:final commentIndex):
        await _onCommentReplayRequested(commentIndex, emit);
      case ObserverForegroundDeactivated():
        await _onForegroundDeactivated(emit);
      case ObserverSuspended():
        await _onSuspended(emit);
      case ObserverResumed():
        await _onResumed(emit);
      case _ObserverTicked():
        _onTicked(emit);
      case _SceneChanged(:final scene):
        if (scene != state.scene) emit(state.copyWith(scene: scene));
      case _ModelUpdateReceived(:final update):
        await _onModelUpdate(update, emit);
      case _GenerationUpdateReceived(:final update):
        await _onGenerationUpdate(update, emit);
      case _SpeechUpdateReceived(:final update):
        await _onSpeechUpdate(update, emit);
      case _VoiceInputUpdateReceived(:final update):
        await _onVoiceInputUpdate(update, emit);
    }
  }

  // ── Startup and observation controls ──

  void _onStarted(Emitter<ObserverState> emit) {
    if (state.started || _closing) return;

    _ensureSceneSubscription();
    _modelSession.activate();
    final projected = _projectModelState(
      state.copyWith(
        started: true,
        observationEnabled: true,
        scene: _sceneSource.current,
      ),
      _modelSession.current,
    );
    if (!_acceptsForegroundWork) {
      emit(
        projected.copyWith(
          foregroundActive: false,
          modelStatus: ObserverModelStatus.suspended,
          asrModelStatus: ObserverModelStatus.suspended,
          voicePhase: VoiceAgentPhase.suspended,
          modelDownloadProgress: () => null,
          modelFailure: () => null,
        ),
      );
      return;
    }

    emit(
      _preparingState(projected).copyWith(
        asrModelStatus: ObserverModelStatus.loading,
        voicePhase: VoiceAgentPhase.preparing,
        asrModelDownloadProgress: () => null,
        asrModelFailure: () => null,
        voiceFailure: () => null,
      ),
    );
    _replaceObservationTimer();
    _modelSession.requestPreparation();
    unawaited(_voiceInputSession.prepareModel());
  }

  Future<void> _onModelRetryRequested(Emitter<ObserverState> emit) async {
    if (_closing ||
        !state.started ||
        !_acceptsForegroundWork ||
        _modelSession.preparationActive ||
        state.modelStatus != ObserverModelStatus.failure) {
      return;
    }

    emit(state.copyWith(voicePhase: VoiceAgentPhase.unavailable));
    final voicePause = await _voiceInputSession.pause();
    if (emit.isDone || _closing || !_acceptsForegroundWork) return;
    if (voicePause case AppError<void>(:final failure)) {
      emit(
        state.copyWith(
          voicePhase: VoiceAgentPhase.failure,
          voiceFailure: () => failure,
        ),
      );
      return;
    }
    emit(_preparingState(state));
    _modelSession.requestPreparation();
  }

  void _onObservationStarted(Emitter<ObserverState> emit) {
    if (_closing || !state.started || state.observationEnabled) return;
    emit(
      state.copyWith(observationEnabled: true, automaticFailure: () => null),
    );
    _replaceObservationTimer();
  }

  Future<void> _onObservationStopped(Emitter<ObserverState> emit) async {
    if (_closing || !state.started || !state.observationEnabled) return;

    _cancelObservationTimer();
    if (_generationSession.active?.kind != ObserverGenerationKind.automatic) {
      emit(
        state.copyWith(
          observationEnabled: false,
          automaticFailure: () => null,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        observationEnabled: false,
        automaticFailure: () => null,
      ),
    );
    try {
      await _generationSession.cancel();
    } finally {
      if (!emit.isDone && !_closing) {
        emit(
          state.copyWith(
            activeGeneration: () => null,
            automaticDraft: '',
          ),
        );
      }
    }
  }

  void _onIntervalSelected(
    ObserverInterval interval,
    Emitter<ObserverState> emit,
  ) {
    if (_closing || !state.started || interval == state.interval) return;
    emit(state.copyWith(interval: interval));
    _replaceObservationTimer();
  }

  // ── Manual dialogue ──

  /// Manual requests have priority: they cancel an automatic comment before
  /// starting, while another manual request is ignored until it settles.
  Future<void> _onPromptSubmitted(
    String rawPrompt,
    Emitter<ObserverState> emit,
  ) async {
    final prompt = rawPrompt.trim();
    if (_closing ||
        !_acceptsForegroundWork ||
        !state.canSubmit ||
        prompt.isEmpty ||
        prompt.length > manualPromptCharacterLimit) {
      return;
    }

    emit(state.copyWith(voicePhase: VoiceAgentPhase.unavailable));
    final voicePause = await _voiceInputSession.pause();
    if (emit.isDone || _closing || !_acceptsForegroundWork) return;
    if (voicePause case AppError<void>(:final failure)) {
      emit(
        state.copyWith(
          voicePhase: VoiceAgentPhase.failure,
          voiceFailure: () => failure,
        ),
      );
      return;
    }

    if (_speechSession.isActive) {
      // Manual dialogue has priority over audible commentary. Invalidate the
      // visible speech target before awaiting native stop so no late terminal
      // callback can reclaim the next utterance.
      final commentIndex = state.activeSpeechCommentIndex;
      emit(
        state.copyWith(
          activeSpeechCommentIndex: () => null,
          speechFailure: () => null,
        ),
      );
      final stopResult = await _speechSession.stop();
      if (emit.isDone || _closing || !_acceptsForegroundWork) return;
      if (stopResult case AppError<void>(:final failure)) {
        emit(
          state.copyWith(
            activeSpeechCommentIndex: () => commentIndex,
            speechFailure: () => failure,
          ),
        );
        return;
      }
    }

    if (_generationSession.active?.kind == ObserverGenerationKind.automatic) {
      emit(
        state.copyWith(
          activeGeneration: () => null,
          automaticDraft: '',
          automaticFailure: () => null,
        ),
      );
      await _generationSession.cancel();
      if (emit.isDone || _closing || !_acceptsForegroundWork) return;
    }
    _beginManualGeneration(prompt, emit);
  }

  Future<void> _onAnswerRetryRequested(Emitter<ObserverState> emit) async {
    if (!state.canRetryAnswer) return;
    await _onPromptSubmitted(state.manualDraftPrompt, emit);
  }

  void _beginManualGeneration(String prompt, Emitter<ObserverState> emit) {
    final request = _requestBuilder.manual(
      prompt: prompt,
      scene: _sceneSource.current,
      dialogue: state.messages,
      previousComment: state.previousComment,
    );

    final generation = _generationSession.startManual(request);
    if (generation == null) return;
    emit(
      state.copyWith(
        activeGeneration: () => ObserverGenerationKind.manual,
        manualDraftPrompt: prompt,
        manualDraftResponse: '',
        manualFailure: () => null,
        voicePhase: VoiceAgentPhase.unavailable,
      ),
    );
  }

  Future<void> _onManualGenerationCancelled(Emitter<ObserverState> emit) async {
    if (_closing || _generationSession.active?.kind != ObserverGenerationKind.manual) {
      return;
    }
    try {
      await _generationSession.cancel();
    } finally {
      if (!emit.isDone && !_closing) {
        emit(_withoutGenerationDrafts(state));
        unawaited(_voiceInputSession.watch());
      }
    }
  }

  // ── Model state ──

  Future<void> _onModelUpdate(
    ObserverModelUpdate update,
    Emitter<ObserverState> emit,
  ) async {
    switch (update) {
      case ObserverModelStateChanged(:final state):
        await _onModelStoreStateReceived(state, emit);
      case ObserverModelPreparationCompleted(:final result):
        _onModelPreparationFinished(result, emit);
    }
  }

  Future<void> _onModelStoreStateReceived(
    QwenModelStoreState storeState,
    Emitter<ObserverState> emit,
  ) async {
    if (_closing || !state.started) return;
    if (!_acceptsForegroundWork && storeState.phase != ModelStorePhase.suspended) {
      return;
    }

    final nextStatus = _observerStatusFor(storeState.phase);
    var projected = state;
    if (nextStatus != ObserverModelStatus.ready && state.isGenerating) {
      projected = _withoutGenerationDrafts(state);
      await _generationSession.cancel();
      if (emit.isDone || _closing) return;
    }
    emit(_projectModelState(projected, storeState));
  }

  void _onModelPreparationFinished(
    AppResult<VerifiedModelArtifact> result,
    Emitter<ObserverState> emit,
  ) {
    if (!_acceptsForegroundWork || _closing) return;
    switch (result) {
      case AppSuccess<VerifiedModelArtifact>():
        emit(
          state.copyWith(
            modelStatus: ObserverModelStatus.ready,
            modelDownloadProgress: () => null,
            modelFailure: () => null,
          ),
        );
        if (_canKeepVoiceRecognitionArmed) {
          unawaited(_voiceInputSession.watch());
        }
      case AppError<VerifiedModelArtifact>(:final failure):
        emit(
          state.copyWith(
            modelStatus: ObserverModelStatus.failure,
            modelDownloadProgress: () => null,
            modelFailure: () => failure,
          ),
        );
    }
  }

  // ── Owned producers and shutdown ──

  void _ensureSceneSubscription() {
    _sceneSubscription ??= _sceneSource.changes.listen((scene) {
      if (!_closing && !isClosed) add(_SceneChanged(scene));
    });
  }

  void _forwardModelUpdate(ObserverModelUpdate update) {
    if (!_closing && !isClosed) add(_ModelUpdateReceived(update));
  }

  void _forwardGenerationUpdate(ObserverGenerationUpdate update) {
    if (!_closing && !isClosed) add(_GenerationUpdateReceived(update));
  }

  void _forwardSpeechUpdate(ObserverSpeechCompleted update) {
    if (!_closing && !isClosed) add(_SpeechUpdateReceived(update));
  }

  void _forwardVoiceInputUpdate(ObserverVoiceInputUpdate update) {
    if (!_closing && !isClosed) add(_VoiceInputUpdateReceived(update));
  }

  void _forwardTimerTick() {
    if (!_closing && !isClosed) add(const _ObserverTicked());
  }

  void _replaceObservationTimer() {
    _cancelObservationTimer();
    if (_closing || !_acceptsForegroundWork || !state.started || !state.observationEnabled) {
      return;
    }
    _timerController.replace(state.interval);
  }

  void _cancelObservationTimer() => _timerController.stop();

  ObserverState _preparingState(ObserverState current) {
    return current.copyWith(
      modelStatus: ObserverModelStatus.loading,
      modelDownloadProgress: () => null,
      modelFailure: () => null,
    );
  }

  ObserverState _projectModelState(
    ObserverState current,
    QwenModelStoreState storeState,
  ) {
    return current.copyWith(
      modelStatus: _observerStatusFor(storeState.phase),
      modelDownloadProgress: () => storeState.downloadProgress,
      modelFailure: () => storeState.failure,
    );
  }

  ObserverState _withoutGenerationDrafts(ObserverState current) {
    return current.copyWith(
      activeGeneration: () => null,
      manualDraftPrompt: '',
      manualDraftResponse: '',
      voiceQuestionDraft: '',
      voiceAnswerDraft: '',
      automaticDraft: '',
      manualFailure: () => null,
      voiceFailure: () => null,
      automaticFailure: () => null,
    );
  }

  @override
  Future<void> close() {
    final existingTask = _closeTask;
    if (existingTask != null) return existingTask;

    _closing = true;
    _acceptsForegroundWork = false;
    _timerController.close();
    final blocClose = super.close();
    final sceneCancellation = _sceneSubscription?.cancel();
    _sceneSubscription = null;
    final task = Future.wait<void>([
      blocClose,
      ?sceneCancellation,
      _modelSession.close(),
      _generationSession.close(),
      _speechSession.close().then<void>((_) {}),
      _voiceInputSession.close().then<void>((_) {}),
    ]);
    _closeTask = task;
    return task;
  }
}

ObserverModelStatus _observerStatusFor(ModelStorePhase phase) {
  return switch (phase) {
    ModelStorePhase.idle => ObserverModelStatus.idle,
    ModelStorePhase.loading => ObserverModelStatus.loading,
    ModelStorePhase.downloading => ObserverModelStatus.downloading,
    ModelStorePhase.verifying => ObserverModelStatus.verifying,
    ModelStorePhase.ready => ObserverModelStatus.ready,
    ModelStorePhase.failure => ObserverModelStatus.failure,
    ModelStorePhase.suspended => ObserverModelStatus.suspended,
  };
}
