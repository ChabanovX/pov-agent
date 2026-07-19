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

/// A user or lifecycle intent reconciled with the native observation session.
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

/// A state machine that reconciles intent with one observation session.
///
/// Intent remains responsive while camera and model retries execute in one
/// sequential reconciliation bucket. Native callbacks are normalized by the
/// observation adapter before this Bloc receives them.
final class CameraBloc extends Bloc<CameraEvent, CameraState> {
  /// Creates a camera state machine backed by [_controller].
  ///
  /// Intent and runtime events are handled sequentially. Native operations are
  /// serialized through reconciliation while newer intent updates desired
  /// state immediately.
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
  int _discoveryRequest = 0;
  int _completedDiscoveryRequest = 0;
  int _modelRetryRequest = 0;
  int _completedModelRetryRequest = 0;
  int _observationRetryRequest = 0;
  int _completedObservationRetryRequest = 0;
  bool _observationRetryInProgress = false;
  bool _nativeEnabled = false;
  CameraLens? _nativeLens;

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
            status: _nativeEnabled ? state.status : CameraStatus.disabled,
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
    // Concurrency policy: model, observation, and native camera operations are
    // serialized here while newer intent may update desired state immediately.
    while (!emit.isDone) {
      if (_hasPendingObservationRetry) {
        final canContinue = await _retryObservation(emit);
        if (!canContinue) return;
        continue;
      }
      if (_hasPendingModelRetry) {
        final canContinue = await _retryModel(emit);
        if (!canContinue) return;
        continue;
      }
      if (_hasPendingDiscovery) {
        final canContinue = await _discoverCameras(emit);
        if (!canContinue) return;
        continue;
      }

      final settled = await _reconcileNativePower(emit);
      if (settled) return;
    }
  }

  Future<bool> _retryModel(Emitter<CameraState> emit) async {
    final request = _modelRetryRequest;
    final result = await _controller.retryModel();
    if (emit.isDone) return false;
    if (request != _modelRetryRequest) return true;
    _completedModelRetryRequest = request;

    switch (result) {
      case AppSuccess<void>():
        return true;
      case AppError<void>(:final failure):
        emit(
          state.copyWith(
            modelStatus: ObservationModelStatus.failure,
            modelFailure: () => failure,
          ),
        );
        return false;
    }
  }

  Future<bool> _retryObservation(Emitter<CameraState> emit) async {
    final request = _observationRetryRequest;
    final result = await _controller.retryObservation();
    if (emit.isDone) return false;
    if (request != _observationRetryRequest) return true;
    _completedObservationRetryRequest = request;

    switch (result) {
      case AppSuccess<void>():
        return true;
      case AppError<void>(:final failure):
        _observationRetryInProgress = false;
        emit(
          state.copyWith(
            observationFailure: () => failure,
          ),
        );
        return false;
    }
  }

  Future<bool> _discoverCameras(Emitter<CameraState> emit) async {
    final request = _discoveryRequest;
    final result = await _controller.init();
    if (emit.isDone) return false;

    if (request != _discoveryRequest) {
      return true;
    }
    _completedDiscoveryRequest = request;

    switch (result) {
      case AppSuccess(value: final capabilities):
        _emitCapabilities(emit, capabilities);
        return true;
      case AppError(:final failure):
        _emitCameraFailure(emit, failure);
        return false;
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
        status: _nativeEnabled ? CameraStatus.enabled : CameraStatus.disabled,
        selectedLens: selectedLens,
        availableLenses: capabilities.availableLenses,
        surfaceMounted: true,
        cameraFailure: () => null,
      ),
    );
  }

  Future<bool> _reconcileNativePower(
    Emitter<CameraState> emit,
  ) async {
    if (!_shouldEnable) {
      return _disableNativeCamera(emit);
    }
    return _enableSelectedLens(emit);
  }

  Future<bool> _disableNativeCamera(
    Emitter<CameraState> emit,
  ) async {
    if (!_nativeEnabled) {
      if (state.cameraFailure == null && state.status != CameraStatus.disabled) {
        emit(
          state.copyWith(
            status: CameraStatus.disabled,
            cameraFailure: () => null,
          ),
        );
      }
      return true;
    }

    final result = await _controller.disable();
    if (emit.isDone) return true;

    switch (result) {
      case AppSuccess<void>():
        _nativeEnabled = false;
        _nativeLens = null;
        if (_shouldEnable) return false;
        emit(
          state.copyWith(
            status: CameraStatus.disabled,
            cameraFailure: () => null,
          ),
        );
        return true;
      case AppError<void>(:final failure):
        if (_shouldEnable) return false;
        _emitCameraFailure(emit, failure);
        return true;
    }
  }

  Future<bool> _enableSelectedLens(
    Emitter<CameraState> emit,
  ) async {
    final targetLens = state.selectedLens;
    if (_nativeEnabled && _nativeLens == targetLens) {
      if (state.status != CameraStatus.enabled || state.cameraFailure != null) {
        emit(
          state.copyWith(
            status: CameraStatus.enabled,
            cameraFailure: () => null,
          ),
        );
      }
      return true;
    }

    emit(
      state.copyWith(
        status: _nativeEnabled ? CameraStatus.switching : CameraStatus.initializing,
        cameraFailure: () => null,
      ),
    );
    final result = await _controller.enable(targetLens);
    if (emit.isDone) return true;

    switch (result) {
      case AppSuccess<void>():
        _nativeEnabled = true;
        _nativeLens = targetLens;
        if (!_shouldEnable || state.selectedLens != targetLens) {
          return false;
        }
        emit(
          state.copyWith(
            status: CameraStatus.enabled,
            cameraFailure: () => null,
          ),
        );
        return true;
      case AppError<void>(:final failure):
        _nativeEnabled = false;
        _nativeLens = null;
        if (!_shouldEnable || state.selectedLens != targetLens) {
          return false;
        }
        _emitCameraFailure(emit, failure);
        return true;
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
        'Could not release the YOLO observation controller cleanly.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
