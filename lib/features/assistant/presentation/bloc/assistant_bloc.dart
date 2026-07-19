import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_state.dart';
import 'package:pov_agent/features/assistant/presentation/services/assistant_generation_runner.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

const _manualHistoryMessageLimit = 2;

/// An input accepted by [AssistantBloc].
sealed class AssistantEvent {
  /// Creates an assistant event.
  const AssistantEvent();
}

/// Requests lazy model preparation on the assistant tab's first visit.
final class AssistantStarted extends AssistantEvent {
  /// Creates an assistant-start intent.
  const AssistantStarted();
}

/// Retries the latest model preparation failure.
final class AssistantModelRetryRequested extends AssistantEvent {
  /// Creates a model-retry intent.
  const AssistantModelRetryRequested();
}

/// Starts a manual `/think` dialogue turn for [prompt].
final class AssistantPromptSubmitted extends AssistantEvent {
  /// Creates a manual prompt intent.
  const AssistantPromptSubmitted(this.prompt);

  /// The user-entered prompt.
  final String prompt;
}

/// Cooperatively cancels the active manual generation.
final class AssistantGenerationCancelled extends AssistantEvent {
  /// Creates a generation-cancel intent.
  const AssistantGenerationCancelled();
}

/// Resubmits the uncommitted prompt from the latest failed answer.
final class AssistantAnswerRetryRequested extends AssistantEvent {
  /// Creates an answer-retry intent.
  const AssistantAnswerRetryRequested();
}

/// An ordered foreground lifecycle intent accepted by [AssistantBloc].
sealed class AssistantLifecycleEvent extends AssistantEvent {
  /// Creates an assistant lifecycle event.
  const AssistantLifecycleEvent();
}

/// Suspends foreground model and generation work.
final class AssistantSuspended extends AssistantLifecycleEvent {
  /// Creates a lifecycle-suspend intent.
  const AssistantSuspended();
}

/// Restarts model preparation after foreground resume, if previously started.
final class AssistantResumed extends AssistantLifecycleEvent {
  /// Creates a lifecycle-resume intent.
  const AssistantResumed();
}

sealed class _AssistantModelEvent extends AssistantEvent {
  const _AssistantModelEvent();
}

final class _ModelStoreStateReceived extends _AssistantModelEvent {
  const _ModelStoreStateReceived(this.storeState);

  final ModelStoreState storeState;
}

final class _ModelPreparationFinished extends _AssistantModelEvent {
  const _ModelPreparationFinished({
    required this.epoch,
    required this.result,
  });

  final int epoch;
  final AppResult<VerifiedModelArtifact> result;
}

sealed class _AssistantGenerationEvent extends AssistantEvent {
  const _AssistantGenerationEvent(this.runId);

  final int runId;
}

final class _GenerationChunkReceived extends _AssistantGenerationEvent {
  const _GenerationChunkReceived({
    required int runId,
    required this.chunk,
  }) : super(runId);

  final String chunk;
}

final class _GenerationFinished extends _AssistantGenerationEvent {
  const _GenerationFinished({
    required int runId,
    required this.result,
  }) : super(runId);

  final AppResult<String> result;
}

/// Owns the foreground assistant session projected by [AssistantState].
///
/// Responsibilities:
/// - Lazily observes and prepares the app-owned [ModelStore].
/// - Builds bounded manual Qwen prompts from committed session history.
/// - Projects one [AssistantGenerationRunner] into a visible answer draft.
/// - Invalidates stale preparation and generation completions before suspend,
///   cancellation, or close can await resource teardown.
///
/// The Bloc owns its subscriptions and in-flight observation tasks, but not the
/// injected store or generator. Process-level composition closes those ports
/// after this Bloc has stopped consuming them.
final class AssistantBloc extends Bloc<AssistantEvent, AssistantState> {
  /// Creates an idle assistant session without starting model preparation.
  factory AssistantBloc({
    required ModelStore modelStore,
    required CommentGenerator commentGenerator,
    required QwenPromptBuilder promptBuilder,
  }) {
    return AssistantBloc._(modelStore, commentGenerator, promptBuilder);
  }

  AssistantBloc._(
    this._modelStore,
    CommentGenerator commentGenerator,
    this._promptBuilder,
  ) : super(AssistantState()) {
    _generationRunner = AssistantGenerationRunner(
      commentGenerator: commentGenerator,
      onUpdate: _forwardGenerationUpdate,
    );
    // Each event family preserves its own order. Suspend and resume share one
    // family so model teardown settles before the next foreground transition;
    // readiness and task slots reject duplicate starts, retries, and submits.
    on<AssistantStarted>(_onStarted, transformer: sequential());
    on<AssistantModelRetryRequested>(
      _onModelRetryRequested,
      transformer: sequential(),
    );
    on<AssistantPromptSubmitted>(
      _onPromptSubmitted,
      transformer: sequential(),
    );
    on<AssistantGenerationCancelled>(
      _onGenerationCancelled,
      transformer: sequential(),
    );
    on<AssistantAnswerRetryRequested>(
      _onAnswerRetryRequested,
      transformer: sequential(),
    );
    on<AssistantLifecycleEvent>(_onLifecycleEvent, transformer: sequential());
    on<_AssistantModelEvent>(_onModelEvent, transformer: sequential());
    on<_AssistantGenerationEvent>(
      _onGenerationEvent,
      transformer: sequential(),
    );
  }

  /// Maximum user-entered characters retained in one manual prompt.
  static const manualPromptCharacterLimit = 320;

  final ModelStore _modelStore;
  final QwenPromptBuilder _promptBuilder;
  late final AssistantGenerationRunner _generationRunner;

  StreamSubscription<ModelStoreState>? _modelStateSubscription;
  Future<void>? _preparationTask;
  Future<void>? _suspensionTask;
  Future<void>? _closeTask;

  var _preparationEpoch = 0;
  int? _currentGenerationRunId;
  var _foregroundActive = true;
  var _closing = false;

  void _onStarted(AssistantStarted event, Emitter<AssistantState> emit) {
    if (state.started || _closing) return;

    _ensureModelStateSubscription();
    final projected = _projectModelState(
      state.copyWith(started: true),
      _modelStore.current,
    );
    if (!_foregroundActive) {
      emit(
        projected.copyWith(
          modelStatus: AssistantModelStatus.suspended,
          modelDownloadProgress: () => null,
          modelFailure: () => null,
        ),
      );
      return;
    }

    emit(_preparingState(projected));
    _requestModelPreparation();
  }

  void _onModelRetryRequested(
    AssistantModelRetryRequested event,
    Emitter<AssistantState> emit,
  ) {
    if (_closing ||
        !state.started ||
        !_foregroundActive ||
        _preparationTask != null ||
        state.modelStatus != AssistantModelStatus.failure) {
      return;
    }

    emit(_preparingState(state));
    _requestModelPreparation();
  }

  void _onPromptSubmitted(
    AssistantPromptSubmitted event,
    Emitter<AssistantState> emit,
  ) {
    _beginGeneration(event.prompt, emit);
  }

  void _onAnswerRetryRequested(
    AssistantAnswerRetryRequested event,
    Emitter<AssistantState> emit,
  ) {
    if (!state.canRetryAnswer) return;
    _beginGeneration(state.draftPrompt, emit);
  }

  void _beginGeneration(String rawPrompt, Emitter<AssistantState> emit) {
    final prompt = rawPrompt.trim();
    if (_closing ||
        !_foregroundActive ||
        !state.canSubmit ||
        _generationRunner.isActive ||
        prompt.isEmpty ||
        prompt.length > manualPromptCharacterLimit) {
      return;
    }

    CommentGenerationRequest request;
    try {
      request = _promptBuilder.manualDialogue(
        prompt: prompt,
        // Keep one completed turn in the model prompt so compile-time context
        // and response budgets retain room; the full transcript stays visible.
        history: _recentPromptHistory(state.messages),
      );
    } on Object catch (error) {
      if (error is ArgumentError) return;
      rethrow;
    }

    final runId = _generationRunner.start(request);
    if (runId == null) return;
    _currentGenerationRunId = runId;
    emit(
      state.copyWith(
        generationStatus: AssistantGenerationStatus.generating,
        draftPrompt: prompt,
        draftResponse: '',
        generationFailure: () => null,
      ),
    );
  }

  Future<void> _onGenerationCancelled(
    AssistantGenerationCancelled event,
    Emitter<AssistantState> emit,
  ) async {
    if (_closing || state.generationStatus != AssistantGenerationStatus.generating) {
      return;
    }

    _currentGenerationRunId = null;
    await _generationRunner.cancel();
    if (emit.isDone || _closing) return;
    emit(_withoutGenerationDraft(state));
  }

  Future<void> _onLifecycleEvent(
    AssistantLifecycleEvent event,
    Emitter<AssistantState> emit,
  ) async {
    switch (event) {
      case AssistantSuspended():
        await _onSuspended(event, emit);
      case AssistantResumed():
        await _onResumed(event, emit);
    }
  }

  Future<void> _onSuspended(
    AssistantSuspended event,
    Emitter<AssistantState> emit,
  ) async {
    if (!_foregroundActive) {
      await _suspensionTask;
      return;
    }
    _foregroundActive = false;
    if (!state.started || _closing) return;

    // Stale work is invalid before cancellation awaits. Neither a late token
    // nor a preparation result may revive foreground state during teardown.
    _preparationEpoch += 1;
    emit(
      _withoutGenerationDraft(state).copyWith(
        modelStatus: AssistantModelStatus.suspended,
        modelDownloadProgress: () => null,
        modelFailure: () => null,
      ),
    );

    late final Future<void> suspensionTask;
    suspensionTask = _suspendResources();
    _suspensionTask = suspensionTask;
    try {
      await suspensionTask;
    } finally {
      if (identical(_suspensionTask, suspensionTask)) {
        _suspensionTask = null;
      }
    }
  }

  Future<void> _onResumed(
    AssistantResumed event,
    Emitter<AssistantState> emit,
  ) async {
    if (_foregroundActive || _closing) return;
    _foregroundActive = true;
    if (!state.started) return;

    await _suspensionTask;
    if (emit.isDone || _closing || !_foregroundActive) return;
    emit(_preparingState(state));
    _requestModelPreparation();
  }

  Future<void> _onModelEvent(
    _AssistantModelEvent event,
    Emitter<AssistantState> emit,
  ) async {
    if (_closing || !state.started) return;

    switch (event) {
      case _ModelStoreStateReceived(:final storeState):
        if (!_foregroundActive && storeState.phase != ModelStorePhase.suspended) {
          return;
        }
        final nextStatus = _assistantStatusFor(storeState.phase);
        if (nextStatus != AssistantModelStatus.ready &&
            state.generationStatus == AssistantGenerationStatus.generating) {
          _currentGenerationRunId = null;
          await _generationRunner.cancel();
          if (emit.isDone || _closing) return;
        }
        emit(
          _projectModelState(
            nextStatus == AssistantModelStatus.ready ? state : _withoutGenerationDraft(state),
            storeState,
          ),
        );
      case _ModelPreparationFinished(:final epoch, :final result):
        if (epoch != _preparationEpoch || !_foregroundActive) return;
        switch (result) {
          case AppSuccess<VerifiedModelArtifact>():
            emit(
              state.copyWith(
                modelStatus: AssistantModelStatus.ready,
                modelDownloadProgress: () => null,
                modelFailure: () => null,
              ),
            );
          case AppError<VerifiedModelArtifact>(:final failure):
            emit(
              state.copyWith(
                modelStatus: AssistantModelStatus.failure,
                modelDownloadProgress: () => null,
                modelFailure: () => failure,
              ),
            );
        }
    }
  }

  void _onGenerationEvent(
    _AssistantGenerationEvent event,
    Emitter<AssistantState> emit,
  ) {
    if (_closing ||
        event.runId != _currentGenerationRunId ||
        state.generationStatus != AssistantGenerationStatus.generating) {
      return;
    }

    switch (event) {
      case _GenerationChunkReceived(:final chunk):
        if (chunk.isEmpty) return;
        emit(
          state.copyWith(draftResponse: '${state.draftResponse}$chunk'),
        );
      case _GenerationFinished(:final result):
        _currentGenerationRunId = null;
        switch (result) {
          case AppSuccess<String>(:final value):
            final answer = value.trim();
            if (answer.isEmpty) {
              emit(
                state.copyWith(
                  generationStatus: AssistantGenerationStatus.failure,
                  generationFailure: () => const UnexpectedFailure(
                    code: 'assistant_empty_response',
                  ),
                ),
              );
              return;
            }
            emit(
              state.copyWith(
                generationStatus: AssistantGenerationStatus.idle,
                messages: [
                  ...state.messages,
                  ConversationMessage.user(state.draftPrompt),
                  ConversationMessage.assistant(answer),
                ],
                draftPrompt: '',
                draftResponse: '',
                generationFailure: () => null,
              ),
            );
          case AppError<String>(:final failure):
            emit(
              state.copyWith(
                generationStatus: AssistantGenerationStatus.failure,
                generationFailure: () => failure,
              ),
            );
        }
    }
  }

  void _ensureModelStateSubscription() {
    _modelStateSubscription ??= _modelStore.states.listen((storeState) {
      if (!_closing && !isClosed) {
        add(_ModelStoreStateReceived(storeState));
      }
    });
  }

  void _forwardGenerationUpdate(AssistantGenerationUpdate update) {
    if (_closing || isClosed) return;
    switch (update) {
      case AssistantGenerationChunk(:final runId, :final chunk):
        add(_GenerationChunkReceived(runId: runId, chunk: chunk));
      case AssistantGenerationCompleted(:final runId, :final result):
        add(_GenerationFinished(runId: runId, result: result));
    }
  }

  void _requestModelPreparation() {
    if (_closing || !_foregroundActive || !state.started || _preparationTask != null) {
      return;
    }

    final epoch = ++_preparationEpoch;
    late final Future<void> task;
    task = _observePreparation(epoch).whenComplete(() {
      if (identical(_preparationTask, task)) _preparationTask = null;
    });
    _preparationTask = task;
    unawaited(task);
  }

  Future<void> _observePreparation(int epoch) async {
    AppResult<VerifiedModelArtifact> result;
    try {
      result = await _modelStore.prepare();
    } on Object catch (error, stackTrace) {
      result = AppError(
        UnexpectedFailure(
          code: 'assistant_model_prepare_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_closing && !isClosed) {
      add(_ModelPreparationFinished(epoch: epoch, result: result));
    }
  }

  Future<void> _suspendResources() async {
    try {
      _currentGenerationRunId = null;
      await _generationRunner.cancel();
    } finally {
      await _modelStore.suspend();
    }
  }

  AssistantState _preparingState(AssistantState current) {
    return current.copyWith(
      modelStatus: AssistantModelStatus.loading,
      modelDownloadProgress: () => null,
      modelFailure: () => null,
    );
  }

  AssistantState _projectModelState(
    AssistantState current,
    ModelStoreState storeState,
  ) {
    return current.copyWith(
      modelStatus: _assistantStatusFor(storeState.phase),
      modelDownloadProgress: () => storeState.downloadProgress,
      modelFailure: () => storeState.failure,
    );
  }

  AssistantState _withoutGenerationDraft(AssistantState current) {
    return current.copyWith(
      generationStatus: AssistantGenerationStatus.idle,
      draftPrompt: '',
      draftResponse: '',
      generationFailure: () => null,
    );
  }

  @override
  Future<void> close() {
    final existingTask = _closeTask;
    if (existingTask != null) return existingTask;

    _closing = true;
    _preparationEpoch += 1;
    final blocClose = super.close();
    final modelStateCancellation = _modelStateSubscription?.cancel();
    _modelStateSubscription = null;
    _currentGenerationRunId = null;
    final task = Future.wait<void>([
      blocClose,
      ?modelStateCancellation,
      _generationRunner.close(),
    ]);
    _closeTask = task;
    return task;
  }
}

AssistantModelStatus _assistantStatusFor(ModelStorePhase phase) {
  return switch (phase) {
    ModelStorePhase.idle => AssistantModelStatus.idle,
    ModelStorePhase.loading => AssistantModelStatus.loading,
    ModelStorePhase.downloading => AssistantModelStatus.downloading,
    ModelStorePhase.verifying => AssistantModelStatus.verifying,
    ModelStorePhase.ready => AssistantModelStatus.ready,
    ModelStorePhase.failure => AssistantModelStatus.failure,
    ModelStorePhase.suspended => AssistantModelStatus.suspended,
  };
}

List<ConversationMessage> _recentPromptHistory(
  List<ConversationMessage> messages,
) {
  if (messages.length <= _manualHistoryMessageLimit) return messages;
  return messages.sublist(messages.length - _manualHistoryMessageLimit);
}
