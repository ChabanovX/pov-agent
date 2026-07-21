part of 'observer_bloc.dart';

/// Keeps speech-specific event policy out of the observer's central queue.
extension _ObserverSpeechPolicy on ObserverBloc {
  /// Muting stops current speech but never disables text observation. Unmuting
  /// does not replay comments skipped while mute was active.
  Future<void> _onSpeechMutedChanged(
    bool muted,
    Emitter<ObserverState> emit,
  ) async {
    if (_closing || !state.started || muted == state.speechMuted) return;

    final target = _speechSession.active?.target ?? _speechTargetForState(state);
    emit(
      state.copyWith(
        speechMuted: muted,
        activeSpeechCommentIndex: muted ? () => null : null,
        activeSpeechMessageIndex: muted ? () => null : null,
        activeVoiceSpeechTurnId: muted ? () => null : null,
        voicePhase: muted && state.activeVoiceSpeechTurnId != null ? VoiceAgentPhase.unavailable : state.voicePhase,
        voiceQuestionDraft: muted && state.activeVoiceSpeechTurnId != null ? '' : state.voiceQuestionDraft,
        voiceTurnId: muted && state.activeVoiceSpeechTurnId != null ? () => null : null,
        speechFailure: () => null,
      ),
    );
    if (!muted || target == null || !_speechSession.isActive) return;

    final result = await _speechSession.stop();
    if (emit.isDone || _closing) return;
    if (result case AppError<void>(:final failure)) {
      emit(_restoreSpeechTarget(state, target, failure));
    } else {
      _armVoiceIfAllowed();
    }
  }

  Future<void> _onSpeechStopped(Emitter<ObserverState> emit) async {
    final target = _speechSession.active?.target ?? _speechTargetForState(state);
    if (_closing || target == null || !_speechSession.isActive) {
      return;
    }

    emit(
      state.copyWith(
        activeSpeechCommentIndex: () => null,
        activeSpeechMessageIndex: () => null,
        activeVoiceSpeechTurnId: () => null,
        voicePhase: target is ObserverVoiceAnswerSpeechTarget ? VoiceAgentPhase.unavailable : state.voicePhase,
        voiceQuestionDraft: target is ObserverVoiceAnswerSpeechTarget ? '' : state.voiceQuestionDraft,
        voiceTurnId: target is ObserverVoiceAnswerSpeechTarget ? () => null : null,
        speechFailure: () => null,
      ),
    );
    final result = await _speechSession.stop();
    if (emit.isDone || _closing) return;
    if (result case AppError<void>(:final failure)) {
      emit(_restoreSpeechTarget(state, target, failure));
    } else {
      _armVoiceIfAllowed();
    }
  }

  Future<void> _onMessageReplayRequested(
    int messageIndex,
    Emitter<ObserverState> emit,
  ) async {
    if (_closing ||
        !_acceptsForegroundWork ||
        !state.started ||
        state.speechMuted ||
        state.isGenerating ||
        _generationSession.isActive ||
        _speechSession.isActive ||
        messageIndex < 0 ||
        messageIndex >= state.messages.length ||
        state.messages[messageIndex].role != ConversationRole.assistant) {
      return;
    }

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

    final speech = _speechSession.startMessage(
      messageIndex: messageIndex,
      text: state.messages[messageIndex].content,
    );
    if (speech == null) return;
    emit(
      state.copyWith(
        activeSpeechMessageIndex: () => messageIndex,
        voicePhase: VoiceAgentPhase.unavailable,
        speechFailure: () => null,
      ),
    );
  }

  Future<void> _onCommentReplayRequested(
    int commentIndex,
    Emitter<ObserverState> emit,
  ) async {
    if (_closing ||
        !_acceptsForegroundWork ||
        !state.started ||
        state.speechMuted ||
        state.isGenerating ||
        _generationSession.isActive ||
        _speechSession.isActive ||
        commentIndex < 0 ||
        commentIndex >= state.comments.length) {
      return;
    }

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

    final speech = _speechSession.start(
      commentIndex: commentIndex,
      text: state.comments[commentIndex].text,
    );
    if (speech == null) return;
    emit(
      state.copyWith(
        activeSpeechCommentIndex: () => commentIndex,
        voicePhase: VoiceAgentPhase.unavailable,
        speechFailure: () => null,
      ),
    );
  }

  Future<void> _onSpeechUpdate(
    ObserverSpeechCompleted update,
    Emitter<ObserverState> emit,
  ) async {
    final active = _speechSession.active;
    if (_closing || active?.runId != update.speech.runId) return;

    switch (update.result) {
      case AppSuccess<void>():
        _speechSession.complete(update.speech.runId);
        switch (update.speech.target) {
          case ObserverCommentSpeechTarget():
            emit(
              state.copyWith(
                activeSpeechCommentIndex: () => null,
                speechFailure: () => null,
              ),
            );
            _armVoiceIfAllowed();
          case ObserverMessageSpeechTarget():
            emit(
              state.copyWith(
                activeSpeechMessageIndex: () => null,
                speechFailure: () => null,
              ),
            );
            _armVoiceIfAllowed();
          case ObserverVoiceAnswerSpeechTarget():
            emit(
              state.copyWith(
                activeVoiceSpeechTurnId: () => null,
                voicePhase: VoiceAgentPhase.unavailable,
                voiceQuestionDraft: '',
                voiceTurnId: () => null,
                voiceFailure: () => null,
                speechFailure: () => null,
              ),
            );
            _armVoiceIfAllowed();
        }
      case AppError<void>(:final failure):
        final stopResult = await _speechSession.stop();
        if (emit.isDone || _closing) return;
        switch ((update.speech.target, stopResult)) {
          case (ObserverCommentSpeechTarget(), AppSuccess<void>()):
            emit(
              state.copyWith(
                activeSpeechCommentIndex: () => null,
                speechFailure: () => failure,
              ),
            );
            _armVoiceIfAllowed();
          case (
            ObserverCommentSpeechTarget(:final commentIndex),
            AppError<void>(:final failure),
          ):
            emit(
              state.copyWith(
                activeSpeechCommentIndex: () => commentIndex,
                speechFailure: () => failure,
              ),
            );
          case (ObserverMessageSpeechTarget(), AppSuccess<void>()):
            emit(
              state.copyWith(
                activeSpeechMessageIndex: () => null,
                speechFailure: () => failure,
              ),
            );
            _armVoiceIfAllowed();
          case (
            ObserverMessageSpeechTarget(:final messageIndex),
            AppError<void>(:final failure),
          ):
            emit(
              state.copyWith(
                activeSpeechMessageIndex: () => messageIndex,
                speechFailure: () => failure,
              ),
            );
          case (ObserverVoiceAnswerSpeechTarget(), AppSuccess<void>()):
            emit(
              state.copyWith(
                activeVoiceSpeechTurnId: () => null,
                voicePhase: VoiceAgentPhase.failure,
                voiceFailure: () => failure,
                speechFailure: () => failure,
              ),
            );
          case (
            ObserverVoiceAnswerSpeechTarget(:final turnId),
            AppError<void>(:final failure),
          ):
            emit(
              state.copyWith(
                activeVoiceSpeechTurnId: () => turnId,
                voicePhase: VoiceAgentPhase.failure,
                voiceFailure: () => failure,
                speechFailure: () => failure,
              ),
            );
        }
    }
  }
}

ObserverState _restoreSpeechTarget(
  ObserverState state,
  ObserverSpeechTarget target,
  AppFailure failure,
) {
  return switch (target) {
    ObserverCommentSpeechTarget(:final commentIndex) => state.copyWith(
      activeSpeechCommentIndex: () => commentIndex,
      speechFailure: () => failure,
    ),
    ObserverMessageSpeechTarget(:final messageIndex) => state.copyWith(
      activeSpeechMessageIndex: () => messageIndex,
      speechFailure: () => failure,
    ),
    ObserverVoiceAnswerSpeechTarget(:final turnId) => state.copyWith(
      activeVoiceSpeechTurnId: () => turnId,
      voicePhase: VoiceAgentPhase.failure,
      voiceFailure: () => failure,
      speechFailure: () => failure,
    ),
  };
}

ObserverSpeechTarget? _speechTargetForState(ObserverState state) {
  if (state.activeSpeechCommentIndex case final commentIndex?) {
    return ObserverCommentSpeechTarget(commentIndex);
  }
  if (state.activeSpeechMessageIndex case final messageIndex?) {
    return ObserverMessageSpeechTarget(messageIndex);
  }
  if (state.activeVoiceSpeechTurnId case final turnId?) {
    return ObserverVoiceAnswerSpeechTarget(turnId);
  }
  return null;
}
