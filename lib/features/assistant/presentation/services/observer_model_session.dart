import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A model-store update forwarded to the owning observer Bloc.
sealed class ObserverModelUpdate {
  const ObserverModelUpdate();
}

/// A model-store state published by the app-owned store.
final class ObserverModelStateChanged extends ObserverModelUpdate {
  /// Creates a store-state update.
  const ObserverModelStateChanged(this.state);

  /// The latest normalized store state.
  final QwenModelStoreState state;
}

/// The terminal result of one epoch-guarded preparation request.
final class ObserverModelPreparationCompleted extends ObserverModelUpdate {
  /// Creates a preparation completion update.
  const ObserverModelPreparationCompleted(this.result);

  /// The verified artifact or normalized preparation failure.
  final AppResult<VerifiedModelArtifact> result;
}

/// Owns Qwen artifact observation, runtime activation, and stale-result epochs.
///
/// Artifact acquisition never loads llama.cpp. This foreground session loads a
/// verified artifact only after the observer starts and unloads it on suspend.
/// Both injected ports remain process-owned and are closed by composition after
/// this session has stopped producing callbacks.
final class ObserverModelSession {
  /// Creates an inactive model session.
  factory ObserverModelSession({
    required QwenModelStore modelStore,
    required CommentGenerator commentGenerator,
    required void Function(ObserverModelUpdate update) onUpdate,
  }) {
    return ObserverModelSession._(
      modelStore,
      commentGenerator,
      onUpdate,
    );
  }

  ObserverModelSession._(
    this._modelStore,
    this._commentGenerator,
    this._onUpdate,
  );

  final QwenModelStore _modelStore;
  final CommentGenerator _commentGenerator;
  final void Function(ObserverModelUpdate update) _onUpdate;
  // This session retains the subscription until its terminal close boundary.
  // ignore: cancel_subscriptions
  StreamSubscription<QwenModelStoreState>? _subscription;
  Future<void>? _preparationTask;
  VerifiedModelArtifact? _runtimeArtifact;
  var _preparationEpoch = 0;
  var _closed = false;

  /// The store state synchronously available to a newly started observer.
  QwenModelStoreState get current {
    final storeState = _modelStore.current;
    if (storeState.phase != ModelStorePhase.ready || _sameArtifact(storeState.artifact, _runtimeArtifact)) {
      return storeState;
    }
    return const QwenModelStoreState.loading();
  }

  /// Whether one preparation request is still settling.
  bool get preparationActive => _preparationTask != null;

  /// Starts forwarding store states without acquiring model resources.
  void activate() {
    if (_closed || _subscription != null) return;
    _subscription = _modelStore.states.listen((state) {
      if (_closed) return;
      if (state.phase != ModelStorePhase.ready) {
        _runtimeArtifact = null;
      }
      _onUpdate(ObserverModelStateChanged(_projectStoreState(state)));
    });
  }

  /// Starts preparation if the task slot is available.
  void requestPreparation() {
    if (_closed || _preparationTask != null) return;
    final epoch = ++_preparationEpoch;
    late final Future<void> task;
    task = _observePreparation(epoch).whenComplete(() {
      if (identical(_preparationTask, task)) _preparationTask = null;
    });
    _preparationTask = task;
    unawaited(task);
  }

  /// Prevents the current preparation completion from reaching presentation.
  void invalidatePreparation() {
    _preparationEpoch += 1;
  }

  /// Suspends acquisition and loaded model resources at the store boundary.
  Future<void> suspend() async {
    invalidatePreparation();
    _runtimeArtifact = null;
    await Future.wait<void>([
      _modelStore.suspend(),
      _commentGenerator.unload(),
    ]);
  }

  /// Stops callbacks and cancels the owned store subscription.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    invalidatePreparation();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    // Do not await `_preparationTask`: the process owner cancels the injected
    // store later, after camera shutdown. Waiting here could invert teardown.
  }

  Future<void> _observePreparation(int epoch) async {
    AppResult<VerifiedModelArtifact> result;
    try {
      final storeState = _modelStore.current;
      final artifact = storeState.artifact;
      result = storeState.phase == ModelStorePhase.ready && artifact != null
          ? AppSuccess<VerifiedModelArtifact>(artifact)
          : await _modelStore.prepare();
    } on Object catch (error, stackTrace) {
      result = AppError(
        UnexpectedFailure(
          code: 'observer_model_prepare_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (_closed || epoch != _preparationEpoch) return;

    if (result case AppSuccess<VerifiedModelArtifact>(:final value)) {
      AppResult<void> loadResult;
      try {
        loadResult = await _commentGenerator.loadModel(value);
      } on Object catch (error, stackTrace) {
        loadResult = AppError(
          UnexpectedFailure(
            code: 'observer_model_load_unexpected',
            message: error.toString(),
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      }
      if (_closed || epoch != _preparationEpoch) return;
      result = switch (loadResult) {
        AppSuccess<void>() => AppSuccess<VerifiedModelArtifact>(value),
        AppError<void>(:final failure) => AppError<VerifiedModelArtifact>(failure),
      };
      if (loadResult is AppSuccess<void>) _runtimeArtifact = value;
    }
    _onUpdate(ObserverModelPreparationCompleted(result));
  }

  QwenModelStoreState _projectStoreState(QwenModelStoreState state) {
    if (state.phase == ModelStorePhase.ready && !_sameArtifact(state.artifact, _runtimeArtifact)) {
      return const QwenModelStoreState.loading();
    }
    return state;
  }
}

bool _sameArtifact(
  VerifiedModelArtifact? first,
  VerifiedModelArtifact? second,
) {
  return first != null &&
      second != null &&
      first.modelId == second.modelId &&
      first.revision == second.revision &&
      first.filePath == second.filePath &&
      first.byteSize == second.byteSize &&
      first.sha256 == second.sha256;
}
