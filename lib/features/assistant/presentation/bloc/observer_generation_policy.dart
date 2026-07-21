part of 'observer_bloc.dart';

/// Projects timer-driven, manual, and voice generation through one runner.
extension _ObserverGenerationPolicy on ObserverBloc {
  void _onTicked(Emitter<ObserverState> emit) {
    if (_closing ||
        !_acceptsForegroundWork ||
        !state.started ||
        !state.observationEnabled ||
        state.modelStatus != ObserverModelStatus.ready ||
        state.isGenerating ||
        _generationSession.isActive ||
        state.isSpeaking ||
        _speechSession.isActive ||
        state.voicePhase == VoiceAgentPhase.wakeDetected ||
        state.voicePhase == VoiceAgentPhase.listening) {
      return;
    }

    // Sample synchronously at handling time. A scene stream event may still be
    // queued behind this tick, but `current` is already the latest contract.
    final scene = _sceneSource.current;
    final request = _requestBuilder.automatic(
      scene: scene,
      previousComment: state.previousComment,
      dialogue: state.messages,
    );
    final generation = _generationSession.startAutomatic(request, scene);
    if (generation == null) return;
    emit(
      state.copyWith(
        scene: scene,
        activeGeneration: () => ObserverGenerationKind.automatic,
        automaticDraft: '',
        automaticFailure: () => null,
      ),
    );
  }

  Future<void> _onGenerationUpdate(
    ObserverGenerationUpdate update,
    Emitter<ObserverState> emit,
  ) async {
    final active = _generationSession.active;
    if (_closing || active?.runId != update.generation.runId) return;
    switch (update) {
      case ObserverGenerationChunk(:final generation, :final chunk):
        if (chunk.isEmpty) return;
        switch (generation.kind) {
          case ObserverGenerationKind.automatic:
            emit(
              state.copyWith(
                automaticDraft: '${state.automaticDraft}$chunk',
              ),
            );
          case ObserverGenerationKind.manual:
            emit(
              state.copyWith(
                manualDraftResponse: '${state.manualDraftResponse}$chunk',
              ),
            );
          case ObserverGenerationKind.voice:
            emit(
              state.copyWith(
                voiceAnswerDraft: '${state.voiceAnswerDraft}$chunk',
              ),
            );
        }
      case ObserverGenerationCompleted(
        :final generation,
        :final result,
      ):
        _generationSession.complete(generation.runId);
        await _onGenerationFinished(generation, result, emit);
    }
  }

  Future<void> _onGenerationFinished(
    ObserverActiveGeneration generation,
    AppResult<String> result,
    Emitter<ObserverState> emit,
  ) async {
    switch ((generation.kind, result)) {
      case (ObserverGenerationKind.automatic, AppSuccess<String>(:final value)):
        final comment = value.trim();
        final observationScene = generation.scene;
        if (comment.isEmpty || observationScene == null) {
          emit(
            _automaticFailureState(
              const UnexpectedFailure(code: 'observer_empty_comment'),
            ),
          );
          return;
        }
        final commentIndex = state.comments.length;
        final committedComment = ObserverComment(
          scene: observationScene,
          text: comment,
        );
        final shouldSpeak = _acceptsForegroundWork && !state.speechMuted && !_speechSession.isActive;
        final voicePause = shouldSpeak ? await _voiceInputSession.pause() : const AppSuccess<void>(null);
        if (emit.isDone || _closing) return;
        final comments = [
          ...state.comments,
          committedComment,
        ];
        if (voicePause case AppError<void>(:final failure)) {
          emit(
            state.copyWith(
              activeGeneration: () => null,
              comments: comments,
              automaticDraft: '',
              automaticFailure: () => null,
              voicePhase: VoiceAgentPhase.failure,
              voiceFailure: () => failure,
            ),
          );
          return;
        }
        final speech = shouldSpeak
            ? _speechSession.start(
                commentIndex: commentIndex,
                text: committedComment.text,
              )
            : null;
        emit(
          state.copyWith(
            activeGeneration: () => null,
            comments: comments,
            automaticDraft: '',
            automaticFailure: () => null,
            activeSpeechCommentIndex: speech == null ? null : () => commentIndex,
            voicePhase: speech == null ? state.voicePhase : VoiceAgentPhase.unavailable,
            voiceFailure: speech == null ? null : () => null,
            speechFailure: speech == null ? null : () => null,
          ),
        );
      case (ObserverGenerationKind.automatic, AppError<String>(:final failure)):
        emit(_automaticFailureState(failure));
      case (ObserverGenerationKind.manual, AppSuccess<String>(:final value)):
        final answer = value.trim();
        if (answer.isEmpty) {
          emit(
            state.copyWith(
              activeGeneration: () => null,
              manualFailure: () => const UnexpectedFailure(code: 'assistant_empty_response'),
            ),
          );
          unawaited(_voiceInputSession.watch());
          return;
        }
        emit(
          state.copyWith(
            activeGeneration: () => null,
            messages: [
              ...state.messages,
              ConversationMessage.user(state.manualDraftPrompt),
              ConversationMessage.assistant(answer),
            ],
            manualDraftPrompt: '',
            manualDraftResponse: '',
            manualFailure: () => null,
          ),
        );
        unawaited(_voiceInputSession.watch());
      case (ObserverGenerationKind.manual, AppError<String>(:final failure)):
        emit(
          state.copyWith(
            activeGeneration: () => null,
            manualFailure: () => failure,
          ),
        );
        unawaited(_voiceInputSession.watch());
      case (ObserverGenerationKind.voice, AppSuccess<String>(:final value)):
        final answer = value.trim();
        final question = state.voiceQuestionDraft.trim();
        final turnId = state.voiceTurnId;
        if (answer.isEmpty || question.isEmpty || turnId == null) {
          emit(
            state.copyWith(
              activeGeneration: () => null,
              voicePhase: VoiceAgentPhase.failure,
              voiceAnswerDraft: '',
              voiceFailure: () => const UnexpectedFailure(
                code: 'voice_assistant_empty_response',
              ),
            ),
          );
          return;
        }
        final speech = !_acceptsForegroundWork || _speechSession.isActive
            ? null
            : _speechSession.startVoice(turnId: turnId, text: answer);
        if (speech == null) {
          emit(
            state.copyWith(
              activeGeneration: () => null,
              voicePhase: VoiceAgentPhase.failure,
              voiceAnswerDraft: '',
              voiceFailure: () => const DeviceUnavailableFailure(
                code: 'voice_answer_speech_unavailable',
              ),
            ),
          );
          return;
        }
        emit(
          state.copyWith(
            activeGeneration: () => null,
            activeVoiceSpeechTurnId: () => turnId,
            voicePhase: VoiceAgentPhase.speaking,
            messages: [
              ...state.messages,
              ConversationMessage.user(question),
              ConversationMessage.assistant(answer),
            ],
            voiceAnswerDraft: '',
            voiceFailure: () => null,
            speechFailure: () => null,
          ),
        );
      case (ObserverGenerationKind.voice, AppError<String>(:final failure)):
        emit(
          state.copyWith(
            activeGeneration: () => null,
            voicePhase: VoiceAgentPhase.failure,
            voiceAnswerDraft: '',
            voiceFailure: () => failure,
          ),
        );
    }
  }

  ObserverState _automaticFailureState(AppFailure failure) {
    return state.copyWith(
      activeGeneration: () => null,
      automaticDraft: '',
      automaticFailure: () => failure,
    );
  }
}
