part of 'observer_bloc.dart';

/// Projects hands-free input through the observer's single ordered queue.
extension _ObserverVoicePolicy on ObserverBloc {
  Future<void> _onMicrophoneSettingsRequested(
    Emitter<ObserverState> emit,
  ) async {
    if (_closing || !state.canOpenMicrophoneSettings) return;
    final result = await _voiceInputSession.openPermissionSettings();
    if (emit.isDone || _closing) return;
    if (result case AppError<void>(:final failure)) {
      emit(state.copyWith(voiceFailure: () => failure));
    }
  }

  Future<void> _onVoiceInputUpdate(
    ObserverVoiceInputUpdate update,
    Emitter<ObserverState> emit,
  ) async {
    if (_closing || !state.started || !state.handsFreeEnabled) return;
    switch (update) {
      case ObserverVoiceModelStateChanged(:final state):
        _onVoiceModelStateChanged(state, emit);
      case ObserverVoiceModelLoadFailed(:final failure):
        emit(
          state.copyWith(
            asrModelStatus: ObserverModelStatus.failure,
            asrModelDownloadProgress: () => null,
            asrModelFailure: () => failure,
            voicePhase: VoiceAgentPhase.failure,
            voiceFailure: () => failure,
          ),
        );
      case ObserverVoiceWatching():
        if (!_canEnterVoiceWatching) {
          await _voiceInputSession.pause();
          return;
        }
        emit(
          state.copyWith(
            asrModelStatus: ObserverModelStatus.ready,
            asrModelDownloadProgress: () => null,
            asrModelFailure: () => null,
            voicePhase: VoiceAgentPhase.watching,
            voiceTurnId: () => null,
            voiceQuestionDraft: '',
            voiceAnswerDraft: '',
            voiceFailure: () => null,
          ),
        );
      case ObserverVoiceWakeDetected(
        :final turnId,
        :final trailingTranscript,
      ):
        if (!_acceptsForegroundWork || state.voicePhase != VoiceAgentPhase.watching || state.isSpeaking) {
          await _voiceInputSession.pause();
          return;
        }
        emit(
          state.copyWith(
            voicePhase: VoiceAgentPhase.wakeDetected,
            voiceTurnId: () => turnId,
            voiceQuestionDraft: trailingTranscript,
            voiceAnswerDraft: '',
            voiceFailure: () => null,
          ),
        );
        if (_generationSession.active?.kind == ObserverGenerationKind.automatic) {
          emit(
            state.copyWith(
              activeGeneration: () => null,
              automaticDraft: '',
              automaticFailure: () => null,
            ),
          );
          await _generationSession.cancel();
        }
      case ObserverVoiceListeningStarted(:final turnId, :final transcript):
        if (!_matchesVoiceTurn(turnId) || state.voicePhase != VoiceAgentPhase.wakeDetected) {
          return;
        }
        emit(
          state.copyWith(
            voicePhase: VoiceAgentPhase.listening,
            voiceQuestionDraft: transcript,
          ),
        );
      case ObserverVoiceTranscriptChanged(:final turnId, :final transcript):
        if (!_matchesVoiceTurn(turnId) || state.voicePhase != VoiceAgentPhase.listening) {
          return;
        }
        emit(state.copyWith(voiceQuestionDraft: transcript));
      case ObserverVoiceQuestionCompleted(:final turnId, :final question):
        await _onVoiceQuestionCompleted(turnId, question, emit);
      case ObserverVoiceInputFailed(:final turnId, :final failure):
        if (turnId != null && !_matchesVoiceTurn(turnId)) return;
        emit(
          state.copyWith(
            voicePhase: VoiceAgentPhase.failure,
            voiceTurnId: turnId == null ? () => null : null,
            voiceAnswerDraft: '',
            voiceFailure: () => failure,
          ),
        );
    }
  }

  void _onVoiceModelStateChanged(
    ModelStoreState<VerifiedAsrModelBundle> modelState,
    Emitter<ObserverState> emit,
  ) {
    if (!state.handsFreeEnabled) return;
    // A suspended store update can already be queued when resume reconciles
    // the synchronous store state. Do not let that prior lifecycle projection
    // overwrite the foreground recovery state.
    if (_acceptsForegroundWork && modelState.phase == ModelStorePhase.suspended) {
      return;
    }
    if (!_acceptsForegroundWork && modelState.phase != ModelStorePhase.suspended) {
      return;
    }
    final status = _observerStatusFor(modelState.phase);
    var phase = state.voicePhase;
    if (status == ObserverModelStatus.failure) {
      phase = VoiceAgentPhase.failure;
    } else if (status == ObserverModelStatus.suspended) {
      phase = VoiceAgentPhase.suspended;
    } else if (status != ObserverModelStatus.ready &&
        phase != VoiceAgentPhase.thinking &&
        phase != VoiceAgentPhase.speaking) {
      phase = VoiceAgentPhase.preparing;
    }
    emit(
      state.copyWith(
        asrModelStatus: status,
        asrModelDownloadProgress: () => modelState.downloadProgress,
        asrModelFailure: () => modelState.failure,
        voicePhase: phase,
        voiceFailure: status == ObserverModelStatus.failure ? () => modelState.failure : null,
      ),
    );
    if (status == ObserverModelStatus.ready) _armVoiceIfAllowed();
  }

  /// Enabling is explicit and single-flight through the Bloc queue. Disabling
  /// invalidates recognition before awaiting native teardown, so a late wake
  /// callback cannot reopen a voice turn after the switch is off.
  Future<void> _onHandsFreeEnabledChanged(
    bool enabled,
    Emitter<ObserverState> emit,
  ) async {
    if (_closing || !state.started || enabled == state.handsFreeEnabled) {
      return;
    }
    if (!enabled) {
      emit(
        state.copyWith(
          handsFreeEnabled: false,
          voicePhase: VoiceAgentPhase.unavailable,
          voiceTurnId: () => null,
          voiceQuestionDraft: '',
          voiceAnswerDraft: '',
          voiceFailure: () => null,
        ),
      );
      final result = await _voiceInputSession.suspend();
      if (emit.isDone || _closing) return;
      if (result case AppError<void>(:final failure)) {
        emit(state.copyWith(voiceFailure: () => failure));
      } else {
        emit(state.copyWith(asrModelStatus: ObserverModelStatus.suspended));
      }
      return;
    }

    emit(
      state.copyWith(
        handsFreeEnabled: true,
        asrModelStatus: _acceptsForegroundWork ? ObserverModelStatus.loading : ObserverModelStatus.suspended,
        voicePhase: _acceptsForegroundWork ? VoiceAgentPhase.preparing : VoiceAgentPhase.suspended,
        asrModelFailure: () => null,
        voiceFailure: () => null,
      ),
    );
    if (!_acceptsForegroundWork) return;
    _voiceRetryRequired = false;
    final result = await _voiceInputSession.prepareModel();
    if (emit.isDone || _closing || !state.handsFreeEnabled) return;
    if (result case AppError<VerifiedAsrModelBundle>(:final failure)) {
      emit(
        state.copyWith(
          asrModelStatus: ObserverModelStatus.failure,
          voicePhase: VoiceAgentPhase.failure,
          asrModelFailure: () => failure,
          voiceFailure: () => failure,
        ),
      );
      return;
    }
    _armVoiceIfAllowed();
  }

  Future<void> _onVoiceQuestionCompleted(
    int turnId,
    String rawQuestion,
    Emitter<ObserverState> emit,
  ) async {
    final question = rawQuestion.trim();
    if (!_matchesVoiceTurn(turnId) ||
        state.voicePhase != VoiceAgentPhase.listening ||
        question.isEmpty ||
        state.modelStatus != ObserverModelStatus.ready ||
        _speechSession.isActive ||
        _generationSession.isActive) {
      if (_matchesVoiceTurn(turnId)) {
        emit(
          state.copyWith(
            voicePhase: VoiceAgentPhase.failure,
            voiceFailure: () => const DeviceUnavailableFailure(
              code: 'voice_assistant_not_ready',
            ),
          ),
        );
      }
      return;
    }

    final request = _requestBuilder.voiceQuestion(
      question: question,
      scene: _sceneSource.current,
      dialogue: state.messages,
      previousComment: state.previousComment,
    );
    final generation = _generationSession.startVoice(request);
    if (generation == null) return;
    emit(
      state.copyWith(
        activeGeneration: () => ObserverGenerationKind.voice,
        voicePhase: VoiceAgentPhase.thinking,
        voiceQuestionDraft: question,
        voiceAnswerDraft: '',
        voiceFailure: () => null,
      ),
    );
  }

  Future<void> _onVoiceRetryRequested(Emitter<ObserverState> emit) async {
    final retainedSpeechTurnId = _speechSession.stopRequiredVoiceTurnId;
    final ownsFailedVoiceSpeech = retainedSpeechTurnId != null && state.activeVoiceSpeechTurnId == retainedSpeechTurnId;
    if (_closing ||
        !_acceptsForegroundWork ||
        !state.started ||
        !state.handsFreeEnabled ||
        state.voicePhase != VoiceAgentPhase.failure ||
        state.isGenerating ||
        (state.isSpeaking && !ownsFailedVoiceSpeech)) {
      return;
    }
    emit(
      state.copyWith(
        voicePhase: VoiceAgentPhase.preparing,
        voiceFailure: () => null,
        asrModelFailure: state.asrModelStatus == ObserverModelStatus.failure ? () => null : null,
      ),
    );
    if (ownsFailedVoiceSpeech) {
      final stopResult = await _speechSession.stop();
      if (emit.isDone || _closing || !_acceptsForegroundWork) return;
      if (stopResult case AppError<void>(:final failure)) {
        emit(
          state.copyWith(
            voicePhase: VoiceAgentPhase.failure,
            voiceFailure: () => failure,
            speechFailure: () => failure,
          ),
        );
        return;
      }
    }
    emit(
      state.copyWith(
        activeVoiceSpeechTurnId: ownsFailedVoiceSpeech ? () => null : null,
        voiceTurnId: () => null,
        voiceQuestionDraft: '',
        voiceAnswerDraft: '',
        speechFailure: ownsFailedVoiceSpeech ? () => null : null,
      ),
    );
    _voiceRetryRequired = false;
    final inputCleanup = await _voiceInputSession.pause();
    if (emit.isDone || _closing || !_acceptsForegroundWork) return;
    if (inputCleanup case AppError<void>(:final failure)) {
      emit(
        state.copyWith(
          voicePhase: VoiceAgentPhase.failure,
          voiceFailure: () => failure,
        ),
      );
      return;
    }
    await _voiceInputSession.watch();
  }

  bool _matchesVoiceTurn(int turnId) => state.voiceTurnId == turnId;

  bool get _canEnterVoiceWatching {
    final generationKind = _generationSession.active?.kind ?? state.activeGeneration;
    return _acceptsForegroundWork &&
        state.handsFreeEnabled &&
        state.modelStatus == ObserverModelStatus.ready &&
        state.voiceFailure == null &&
        state.asrModelFailure == null &&
        !state.isSpeaking &&
        !_speechSession.isActive &&
        generationKind != ObserverGenerationKind.manual &&
        generationKind != ObserverGenerationKind.voice;
  }

  bool get _canKeepVoiceRecognitionArmed {
    final generationKind = _generationSession.active?.kind ?? state.activeGeneration;
    return _acceptsForegroundWork &&
        state.handsFreeEnabled &&
        state.asrModelStatus == ObserverModelStatus.ready &&
        state.modelStatus == ObserverModelStatus.ready &&
        state.voiceFailure == null &&
        state.asrModelFailure == null &&
        !state.isSpeaking &&
        !_speechSession.isActive &&
        generationKind != ObserverGenerationKind.manual &&
        generationKind != ObserverGenerationKind.voice;
  }
}
