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

    final commentIndex = state.activeSpeechCommentIndex;
    emit(
      state.copyWith(
        speechMuted: muted,
        activeSpeechCommentIndex: muted ? () => null : null,
        speechFailure: () => null,
      ),
    );
    if (!muted || !_speechSession.isActive) return;

    final result = await _speechSession.stop();
    if (emit.isDone || _closing) return;
    if (result case AppError<void>(:final failure)) {
      emit(
        state.copyWith(
          activeSpeechCommentIndex: () => commentIndex,
          speechFailure: () => failure,
        ),
      );
    }
  }

  Future<void> _onSpeechStopped(Emitter<ObserverState> emit) async {
    if (_closing || !_speechSession.isActive) return;

    final commentIndex = state.activeSpeechCommentIndex;
    emit(
      state.copyWith(
        activeSpeechCommentIndex: () => null,
        speechFailure: () => null,
      ),
    );
    final result = await _speechSession.stop();
    if (emit.isDone || _closing) return;
    if (result case AppError<void>(:final failure)) {
      emit(
        state.copyWith(
          activeSpeechCommentIndex: () => commentIndex,
          speechFailure: () => failure,
        ),
      );
    }
  }

  void _onCommentReplayRequested(
    int commentIndex,
    Emitter<ObserverState> emit,
  ) {
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

    final speech = _speechSession.start(
      commentIndex: commentIndex,
      text: state.comments[commentIndex].text,
    );
    if (speech == null) return;
    emit(
      state.copyWith(
        activeSpeechCommentIndex: () => commentIndex,
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
        emit(
          state.copyWith(
            activeSpeechCommentIndex: () => null,
            speechFailure: () => null,
          ),
        );
      case AppError<void>(:final failure):
        final stopResult = await _speechSession.stop();
        if (emit.isDone || _closing) return;
        switch (stopResult) {
          case AppSuccess<void>():
            emit(
              state.copyWith(
                activeSpeechCommentIndex: () => null,
                speechFailure: () => failure,
              ),
            );
          case AppError<void>(:final failure):
            emit(
              state.copyWith(
                activeSpeechCommentIndex: () => update.speech.commentIndex,
                speechFailure: () => failure,
              ),
            );
        }
    }
  }
}
