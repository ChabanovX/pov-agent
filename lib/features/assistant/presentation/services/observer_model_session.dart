import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
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

/// Owns model observation, preparation tasks, and stale-result epochs.
///
/// The injected store remains process-owned. This session only stops producing
/// callbacks on [close]; process composition closes the store after its Bloc no
/// longer consumes model updates.
final class ObserverModelSession {
  /// Creates an inactive model session.
  factory ObserverModelSession({
    required QwenModelStore modelStore,
    required void Function(ObserverModelUpdate update) onUpdate,
  }) {
    return ObserverModelSession._(modelStore, onUpdate);
  }

  ObserverModelSession._(this._modelStore, this._onUpdate);

  final QwenModelStore _modelStore;
  final void Function(ObserverModelUpdate update) _onUpdate;
  // This session retains the subscription until its terminal close boundary.
  // ignore: cancel_subscriptions
  StreamSubscription<QwenModelStoreState>? _subscription;
  Future<void>? _preparationTask;
  var _preparationEpoch = 0;
  var _closed = false;

  /// The store state synchronously available to a newly started observer.
  QwenModelStoreState get current => _modelStore.current;

  /// Whether one preparation request is still settling.
  bool get preparationActive => _preparationTask != null;

  /// Starts forwarding store states without acquiring model resources.
  void activate() {
    if (_closed || _subscription != null) return;
    _subscription = _modelStore.states.listen((state) {
      if (!_closed) _onUpdate(ObserverModelStateChanged(state));
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
    await _modelStore.suspend();
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
      result = await _modelStore.prepare();
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
    if (!_closed && epoch == _preparationEpoch) {
      _onUpdate(ObserverModelPreparationCompleted(result));
    }
  }
}
