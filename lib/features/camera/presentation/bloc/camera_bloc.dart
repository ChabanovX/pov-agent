import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// An input accepted by [CameraBloc].
sealed class CameraEvent {
  /// Creates a camera event.
  const CameraEvent();
}

/// A user or lifecycle intent reconciled with the observation-controller session.
sealed class CameraIntentEvent extends CameraEvent {
  /// Creates a camera intent event.
  const CameraIntentEvent();
}

/// An intent to initialize the observation session.
final class CameraStarted extends CameraIntentEvent {
  /// Creates a camera-start intent.
  const CameraStarted();
}

/// An intent to retry the currently failed camera operation.
final class CameraRetryRequested extends CameraIntentEvent {
  /// Creates a retry intent.
  const CameraRetryRequested();
}

/// An intent to enable observation with the selected lens.
final class CameraEnableRequested extends CameraIntentEvent {
  /// Creates a camera-enable intent.
  const CameraEnableRequested();
}

/// An intent to keep observation disabled until the user enables it.
final class CameraDisableRequested extends CameraIntentEvent {
  /// Creates a camera-disable intent.
  const CameraDisableRequested();
}

/// An intent to switch to the next available camera lens.
final class CameraLensToggleRequested extends CameraIntentEvent {
  /// Creates a lens-toggle intent.
  const CameraLensToggleRequested();
}

/// An intent indicating whether the observation surface can use resources.
final class CameraSurfaceActivityChanged extends CameraIntentEvent {
  /// Creates a surface-activity intent with the supplied [active] state.
  const CameraSurfaceActivityChanged({required this.active});

  /// Whether the surface is visible while the app is foregrounded.
  final bool active;
}

final class _CameraReconciliationRequested extends CameraEvent {
  const _CameraReconciliationRequested();
}

final class _ObservationRuntimeEventReceived extends CameraEvent {
  const _ObservationRuntimeEventReceived(this.event);

  final ObservationEvent event;
}

enum _ReconciliationOutcome {
  continueWithLatestState,
  settled,
  eventHandlerDone,
}

/// Reconciles camera intent with one observation-controller session.
///
/// Owns three related models:
/// - Desired product state lives in [CameraState]: requested power, surface
///   activity, and selected lens.
/// - Applied controller state is the latest usable assumption after command
///   outcomes; it is invalidated by enable failure, not probed from hardware.
/// - Pending request generations reject superseded discovery and retry
///   completions before they can overwrite newer intent.
///
/// Each registered event family is sequential, but intent, runtime-event, and
/// reconciliation families may interleave. This keeps newer intent responsive
/// while an earlier controller call awaits. Only reconciliation invokes
/// controller lifecycle methods, so those calls never overlap.
///
/// [close] seals event admission, cancels the runtime-event subscription, waits
/// for reconciliation handlers, then releases the controller.
final class CameraBloc extends Bloc<CameraEvent, CameraState> {
  /// Creates a camera state machine backed by [_controller].
  CameraBloc(
    this._controller, {
    bool initiallySurfaceActive = true,
  }) : super(CameraState(surfaceActive: initiallySurfaceActive)) {
    on<CameraIntentEvent>(
      _onIntent,
      transformer: sequential(),
    );
    on<_ObservationRuntimeEventReceived>(
      _onObservationRuntimeEvent,
      transformer: sequential(),
    );
    on<_CameraReconciliationRequested>(
      _onReconciliationRequested,
      transformer: sequential(),
    );
  }

  static final AppLogger _logger = AppLogger('CameraBloc');

  final ObservationController _controller;

  StreamSubscription<ObservationEvent>? _observationSubscription;

  // Each requested/completed pair rejects a stale completion while preserving
  // any newer request for the next reconciliation pass.
  int _discoveryRequest = 0;
  int _completedDiscoveryRequest = 0;
  int _modelRetryRequest = 0;
  int _completedModelRetryRequest = 0;
  int _observationRetryRequest = 0;
  int _completedObservationRetryRequest = 0;

  // A successful retry call only restarts work. Coalesce repeated UI retries
  // until a runtime result or failure confirms the new observation phase.
  bool _observationRetryInProgress = false;

  // Latest usable controller assumption, distinct from desired UI state.
  bool _controllerEnabled = false;
  CameraLens? _controllerLens;

  bool get _hasPendingDiscovery {
    return _completedDiscoveryRequest < _discoveryRequest;
  }

  bool get _hasPendingModelRetry {
    return _completedModelRetryRequest < _modelRetryRequest;
  }

  bool get _hasPendingObservationRetry {
    return _completedObservationRetryRequest < _observationRetryRequest;
  }

  bool get _shouldEnable {
    return state.requestedEnabled && state.surfaceActive && state.availableLenses.isNotEmpty;
  }

  void _onIntent(
    CameraIntentEvent event,
    Emitter<CameraState> emit,
  ) {
    switch (event) {
      case CameraStarted():
        if (state.status != CameraStatus.initial) return;
        _ensureObservationSubscription();
        _requestDiscovery();
        emit(
          state.copyWith(
            status: CameraStatus.initializing,
            modelStatus: ObservationModelStatus.preparing,
            cameraFailure: () => null,
            modelFailure: () => null,
            observationFailure: () => null,
          ),
        );
      case CameraRetryRequested():
        final retryObservation = state.observationFailure != null || _observationRetryInProgress;
        final retryModel = state.modelFailure != null || state.modelStatus == ObservationModelStatus.failure;
        final retryCamera = state.cameraFailure != null || state.status == CameraStatus.failure;
        if (retryObservation) {
          if (!_observationRetryInProgress) {
            _observationRetryInProgress = true;
            _requestObservationRetry();
          }
        } else {
          if (retryModel || !retryCamera) _requestModelRetry();
          if (retryCamera || !retryModel) _requestDiscovery();
        }
        emit(
          state.copyWith(
            status: retryCamera ? CameraStatus.initializing : state.status,
            modelStatus: retryModel ? ObservationModelStatus.preparing : state.modelStatus,
            modelDownloadProgress: retryModel ? () => null : null,
            cameraFailure: retryCamera ? () => null : null,
            modelFailure: retryModel ? () => null : null,
            observationFailure: retryObservation ? () => null : null,
          ),
        );
      case CameraEnableRequested():
        if (state.requestedEnabled && state.status == CameraStatus.enabled) {
          return;
        }
        if (state.availableLenses.isEmpty && !_hasPendingDiscovery) {
          _requestDiscovery();
        }
        emit(
          state.copyWith(
            status: state.availableLenses.isEmpty || state.status == CameraStatus.failure
                ? CameraStatus.initializing
                : state.status,
            requestedEnabled: true,
            cameraFailure: () => null,
            observationFailure: () => null,
          ),
        );
      case CameraDisableRequested():
        if (!state.requestedEnabled && state.status == CameraStatus.disabled) {
          return;
        }
        emit(
          state.copyWith(
            status: _controllerEnabled ? state.status : CameraStatus.disabled,
            requestedEnabled: false,
            cameraFailure: () => null,
          ),
        );
      case CameraLensToggleRequested():
        if (!state.canToggleLens) return;
        final nextLens = state.selectedLens == CameraLens.back ? CameraLens.front : CameraLens.back;
        emit(
          state.copyWith(
            status: state.requestedEnabled && state.surfaceActive ? CameraStatus.switching : CameraStatus.disabled,
            selectedLens: nextLens,
            cameraFailure: () => null,
          ),
        );
      case CameraSurfaceActivityChanged(:final active):
        if (state.surfaceActive == active) return;
        emit(state.copyWith(surfaceActive: active));
    }

    _scheduleReconciliation();
  }

  void _ensureObservationSubscription() {
    _observationSubscription ??= _controller.events.listen((event) {
      if (!isClosed) add(_ObservationRuntimeEventReceived(event));
    });
  }

  void _onObservationRuntimeEvent(
    _ObservationRuntimeEventReceived event,
    Emitter<CameraState> emit,
  ) {
    switch (event.event) {
      case ObservationModelPreparing():
        _observationRetryInProgress = false;
        emit(
          state.copyWith(
            modelStatus: ObservationModelStatus.preparing,
            modelDownloadProgress: () => null,
            detections: const [],
            diagnostics: () => null,
            modelFailure: () => null,
            observationFailure: () => null,
          ),
        );
      case ObservationModelDownloadProgressed(:final progress):
        emit(
          state.copyWith(
            modelStatus: ObservationModelStatus.downloading,
            modelDownloadProgress: () => progress.clamp(0, 1).toDouble(),
            modelFailure: () => null,
            observationFailure: () => null,
          ),
        );
      case ObservationModelReady():
        emit(
          state.copyWith(
            modelStatus: ObservationModelStatus.ready,
            modelDownloadProgress: () => null,
            modelFailure: () => null,
            observationFailure: () => null,
          ),
        );
      case ObservationSourceDiscontinuity():
        emit(
          state.copyWith(
            detections: const [],
            diagnostics: () => null,
            observationFailure: () => null,
          ),
        );
      case ObservationDetectionsUpdated(:final detections):
        _observationRetryInProgress = false;
        emit(
          state.copyWith(
            detections: detections,
            observationFailure: () => null,
          ),
        );
      case ObservationDiagnosticsUpdated(:final diagnostics):
        emit(state.copyWith(diagnostics: () => diagnostics));
      case ObservationFailed(:final failure):
        _observationRetryInProgress = false;
        emit(
          state.copyWith(
            modelStatus: ObservationModelStatus.failure,
            modelDownloadProgress: () => null,
            detections: const [],
            diagnostics: () => null,
            modelFailure: () => failure,
            observationFailure: () => null,
          ),
        );
      case ObservationInferenceFailed(:final failure):
        _observationRetryInProgress = false;
        emit(
          state.copyWith(
            detections: const [],
            diagnostics: () => null,
            observationFailure: () => failure,
          ),
        );
    }
  }

  void _requestDiscovery() {
    _discoveryRequest += 1;
  }

  void _requestModelRetry() {
    _modelRetryRequest += 1;
  }

  void _requestObservationRetry() {
    _observationRetryRequest += 1;
  }

  void _scheduleReconciliation() {
    if (isClosed) return;
    add(const _CameraReconciliationRequested());
  }

  Future<void> _onReconciliationRequested(
    _CameraReconciliationRequested event,
    Emitter<CameraState> emit,
  ) async {
    // Intent handlers run in another event family, so every awaited step must
    // re-read the latest desired state before choosing the next controller call.
    while (!emit.isDone) {
      switch (await _runNextReconciliationStep(emit)) {
        case _ReconciliationOutcome.continueWithLatestState:
          continue;
        case _ReconciliationOutcome.settled:
        case _ReconciliationOutcome.eventHandlerDone:
          return;
      }
    }
  }

  Future<_ReconciliationOutcome> _runNextReconciliationStep(
    Emitter<CameraState> emit,
  ) {
    if (_hasPendingObservationRetry) return _retryObservation(emit);
    if (_hasPendingModelRetry) return _retryModel(emit);
    if (_hasPendingDiscovery) return _discoverCameras(emit);
    return _reconcileControllerPower(emit);
  }

  Future<_ReconciliationOutcome> _retryModel(
    Emitter<CameraState> emit,
  ) async {
    final request = _modelRetryRequest;
    final result = await _controller.retryModel();
    if (emit.isDone) return _ReconciliationOutcome.eventHandlerDone;
    if (request != _modelRetryRequest) {
      return _ReconciliationOutcome.continueWithLatestState;
    }
    _completedModelRetryRequest = request;

    switch (result) {
      case AppSuccess<void>():
        return _ReconciliationOutcome.continueWithLatestState;
      case AppError<void>(:final failure):
        emit(
          state.copyWith(
            modelStatus: ObservationModelStatus.failure,
            modelFailure: () => failure,
          ),
        );
        return _ReconciliationOutcome.settled;
    }
  }

  Future<_ReconciliationOutcome> _retryObservation(
    Emitter<CameraState> emit,
  ) async {
    final request = _observationRetryRequest;
    final result = await _controller.retryObservation();
    if (emit.isDone) return _ReconciliationOutcome.eventHandlerDone;
    if (request != _observationRetryRequest) {
      return _ReconciliationOutcome.continueWithLatestState;
    }
    _completedObservationRetryRequest = request;

    switch (result) {
      case AppSuccess<void>():
        return _ReconciliationOutcome.continueWithLatestState;
      case AppError<void>(:final failure):
        _observationRetryInProgress = false;
        emit(
          state.copyWith(
            observationFailure: () => failure,
          ),
        );
        return _ReconciliationOutcome.settled;
    }
  }

  Future<_ReconciliationOutcome> _discoverCameras(
    Emitter<CameraState> emit,
  ) async {
    final request = _discoveryRequest;
    final result = await _controller.init();
    if (emit.isDone) return _ReconciliationOutcome.eventHandlerDone;

    if (request != _discoveryRequest) {
      return _ReconciliationOutcome.continueWithLatestState;
    }
    _completedDiscoveryRequest = request;

    switch (result) {
      case AppSuccess(value: final capabilities):
        _emitCapabilities(emit, capabilities);
        return _ReconciliationOutcome.continueWithLatestState;
      case AppError(:final failure):
        _emitCameraFailure(emit, failure);
        return _ReconciliationOutcome.settled;
    }
  }

  void _emitCapabilities(
    Emitter<CameraState> emit,
    CameraCapabilities capabilities,
  ) {
    final selectedLens =
        capabilities.availableLenses.contains(
          state.selectedLens,
        )
        ? state.selectedLens
        : capabilities.preferredLens;
    emit(
      state.copyWith(
        status: _controllerEnabled ? CameraStatus.enabled : CameraStatus.disabled,
        selectedLens: selectedLens,
        availableLenses: capabilities.availableLenses,
        surfaceMounted: true,
        cameraFailure: () => null,
      ),
    );
  }

  Future<_ReconciliationOutcome> _reconcileControllerPower(
    Emitter<CameraState> emit,
  ) {
    if (!_shouldEnable) {
      return _disableController(emit);
    }
    return _enableSelectedLens(emit);
  }

  Future<_ReconciliationOutcome> _disableController(
    Emitter<CameraState> emit,
  ) async {
    if (!_controllerEnabled) {
      if (state.cameraFailure == null && state.status != CameraStatus.disabled) {
        emit(
          state.copyWith(
            status: CameraStatus.disabled,
            cameraFailure: () => null,
          ),
        );
      }
      return _ReconciliationOutcome.settled;
    }

    final result = await _controller.disable();
    if (emit.isDone) return _ReconciliationOutcome.eventHandlerDone;

    switch (result) {
      case AppSuccess<void>():
        _controllerEnabled = false;
        _controllerLens = null;
        if (_shouldEnable) {
          return _ReconciliationOutcome.continueWithLatestState;
        }
        emit(
          state.copyWith(
            status: CameraStatus.disabled,
            cameraFailure: () => null,
          ),
        );
        return _ReconciliationOutcome.settled;
      case AppError<void>(:final failure):
        if (_shouldEnable) {
          return _ReconciliationOutcome.continueWithLatestState;
        }
        _emitCameraFailure(emit, failure);
        return _ReconciliationOutcome.settled;
    }
  }

  Future<_ReconciliationOutcome> _enableSelectedLens(
    Emitter<CameraState> emit,
  ) async {
    final targetLens = state.selectedLens;
    if (_controllerEnabled && _controllerLens == targetLens) {
      if (state.status != CameraStatus.enabled || state.cameraFailure != null) {
        emit(
          state.copyWith(
            status: CameraStatus.enabled,
            cameraFailure: () => null,
          ),
        );
      }
      return _ReconciliationOutcome.settled;
    }

    emit(
      state.copyWith(
        status: _controllerEnabled ? CameraStatus.switching : CameraStatus.initializing,
        cameraFailure: () => null,
      ),
    );
    final result = await _controller.enable(targetLens);
    if (emit.isDone) return _ReconciliationOutcome.eventHandlerDone;

    switch (result) {
      case AppSuccess<void>():
        _controllerEnabled = true;
        _controllerLens = targetLens;
        if (!_shouldEnable || state.selectedLens != targetLens) {
          return _ReconciliationOutcome.continueWithLatestState;
        }
        emit(
          state.copyWith(
            status: CameraStatus.enabled,
            cameraFailure: () => null,
          ),
        );
        return _ReconciliationOutcome.settled;
      case AppError<void>(:final failure):
        _controllerEnabled = false;
        _controllerLens = null;
        if (!_shouldEnable || state.selectedLens != targetLens) {
          return _ReconciliationOutcome.continueWithLatestState;
        }
        _emitCameraFailure(emit, failure);
        return _ReconciliationOutcome.settled;
    }
  }

  void _emitCameraFailure(
    Emitter<CameraState> emit,
    AppFailure failure,
  ) {
    emit(
      state.copyWith(
        status: CameraStatus.failure,
        cameraFailure: () => failure,
      ),
    );
  }

  @override
  Future<void> close() async {
    final blocClose = super.close();
    await _observationSubscription?.cancel();
    await blocClose;
    try {
      await _controller.close();
    } on Exception catch (error, stackTrace) {
      _logger.e(
        'Could not release the observation controller cleanly.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
