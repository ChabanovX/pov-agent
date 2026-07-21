part of 'observer_bloc.dart';

/// Coordinates lifecycle quiescence across generation, speech, and the model.
extension _ObserverLifecyclePolicy on ObserverBloc {
  Future<void> _onForegroundDeactivated(Emitter<ObserverState> emit) async {
    if (!_acceptsForegroundWork) return;
    // Reject new work before awaiting cancellation. `state.foregroundActive`
    // becomes false only after quiescence and serves as the runtime's ack.
    _acceptsForegroundWork = false;
    _cancelObservationTimer();
    _modelSession.invalidatePreparation();
    final speechStop = _speechSession.stop();
    await _generationSession.cancel();
    final speechResult = await speechStop;
    if (emit.isDone || _closing) return;
    emit(
      _withoutGenerationDrafts(state).copyWith(
        foregroundActive: false,
        activeSpeechCommentIndex: () => null,
        speechFailure: () => switch (speechResult) {
          AppSuccess<void>() => null,
          AppError<void>(:final failure) => failure,
        },
      ),
    );
  }

  Future<void> _onSuspended(Emitter<ObserverState> emit) async {
    if (_closing || !state.started) return;
    _acceptsForegroundWork = false;
    _cancelObservationTimer();
    emit(
      _withoutGenerationDrafts(state).copyWith(
        foregroundActive: false,
        activeSpeechCommentIndex: () => null,
        modelStatus: ObserverModelStatus.suspended,
        modelDownloadProgress: () => null,
        modelFailure: () => null,
      ),
    );
    final speechStop = _speechSession.stop();
    try {
      await _generationSession.cancel();
    } finally {
      final speechResult = await speechStop;
      if (!emit.isDone && !_closing) {
        emit(
          state.copyWith(
            speechFailure: () => switch (speechResult) {
              AppSuccess<void>() => null,
              AppError<void>(:final failure) => failure,
            },
          ),
        );
      }
      await _modelSession.suspend();
    }
  }

  Future<void> _onResumed(Emitter<ObserverState> emit) async {
    if (_acceptsForegroundWork || _closing) return;

    // A failed lifecycle stop keeps the native boundary occupied. Retry before
    // accepting ticks; if it still fails, restore the Stop target so recovery
    // remains visible instead of presenting an unusable Replay action.
    AppResult<void>? speechRecovery;
    if (_speechSession.isActive) {
      speechRecovery = await _speechSession.stop();
      if (emit.isDone || _closing) return;
    }

    _acceptsForegroundWork = true;
    // Preparation may finish after foreground deactivation but before the
    // platform sends suspension. Reconcile from the store's synchronous state
    // instead of trusting the intentionally frozen presentation projection.
    final storeState = _modelSession.current;
    final needsReload = switch (storeState.phase) {
      ModelStorePhase.idle || ModelStorePhase.suspended => true,
      _ => false,
    };
    var resumedState = state.copyWith(foregroundActive: true);
    if (speechRecovery != null) {
      resumedState = switch (speechRecovery) {
        AppSuccess<void>() => resumedState.copyWith(
          activeSpeechCommentIndex: () => null,
          speechFailure: () => null,
        ),
        AppError<void>(:final failure) => resumedState.copyWith(
          activeSpeechCommentIndex: () => _speechSession.stopRequiredCommentIndex,
          speechFailure: () => failure,
        ),
      };
    }
    final resumed = _projectModelState(resumedState, storeState);
    emit(needsReload ? _preparingState(resumed) : resumed);
    _replaceObservationTimer();
    if (needsReload) _modelSession.requestPreparation();
  }
}
