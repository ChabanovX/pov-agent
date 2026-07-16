import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:some_camera_with_llm/core/logging/app_logger.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/camera_controller.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_state.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

sealed class CameraEvent {
  const CameraEvent();
}

sealed class CameraIntentEvent extends CameraEvent {
  const CameraIntentEvent();
}

final class CameraStarted extends CameraIntentEvent {
  const CameraStarted();
}

final class CameraRetryRequested extends CameraIntentEvent {
  const CameraRetryRequested();
}

final class CameraEnableRequested extends CameraIntentEvent {
  const CameraEnableRequested();
}

final class CameraDisableRequested extends CameraIntentEvent {
  const CameraDisableRequested();
}

final class CameraLensToggleRequested extends CameraIntentEvent {
  const CameraLensToggleRequested();
}

final class CameraSurfaceActivityChanged extends CameraIntentEvent {
  const CameraSurfaceActivityChanged({required this.active});

  final bool active;
}

final class _CameraReconciliationRequested extends CameraEvent {
  const _CameraReconciliationRequested();
}

/// Reconciles current camera intent with one serialized native camera session.
///
/// Responsibilities:
/// - Apply visibility and user intent without waiting for native I/O.
/// - Discover available front and rear lenses.
/// - Serialize native enable, disable, and lens replacement operations.
/// - Ignore stale native results when newer intent has already arrived.
/// - Normalize camera results into presentation state.
final class CameraBloc extends Bloc<CameraEvent, CameraState> {
  CameraBloc(
    this._controller, {
    bool initiallySurfaceActive = true,
  }) : super(CameraState(surfaceActive: initiallySurfaceActive)) {
    on<CameraIntentEvent>(
      _onIntent,
      transformer: sequential(),
    );
    on<_CameraReconciliationRequested>(
      _onReconciliationRequested,
      transformer: sequential(),
    );
  }

  static final AppLogger _logger = AppLogger('CameraBloc');

  final CameraController _controller;

  int _discoveryRequest = 0;
  int _completedDiscoveryRequest = 0;
  bool _nativeEnabled = false;
  CameraLens? _nativeLens;

  bool get _hasPendingDiscovery {
    return _completedDiscoveryRequest < _discoveryRequest;
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
        _requestDiscovery();
        emit(
          state.copyWith(
            status: CameraStatus.initializing,
            failure: () => null,
          ),
        );
      case CameraRetryRequested():
        _requestDiscovery();
        emit(
          state.copyWith(
            status: CameraStatus.initializing,
            failure: () => null,
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
            failure: () => null,
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
            failure: () => null,
          ),
        );
      case CameraLensToggleRequested():
        if (!state.canToggleLens) return;
        final nextLens = state.selectedLens == CameraLens.back ? CameraLens.front : CameraLens.back;
        emit(
          state.copyWith(
            status: state.requestedEnabled && state.surfaceActive ? CameraStatus.switching : CameraStatus.disabled,
            selectedLens: nextLens,
            failure: () => null,
          ),
        );
      case CameraSurfaceActivityChanged(:final active):
        if (state.surfaceActive == active) return;
        emit(state.copyWith(surfaceActive: active));
    }

    _scheduleReconciliation();
  }

  void _requestDiscovery() {
    _discoveryRequest += 1;
  }

  void _scheduleReconciliation() {
    if (isClosed) return;
    add(const _CameraReconciliationRequested());
  }

  Future<void> _onReconciliationRequested(
    _CameraReconciliationRequested event,
    Emitter<CameraState> emit,
  ) async {
    // Concurrency policy: every native operation runs in this single sequential
    // event bucket, while intent events may update the desired state immediately.
    while (!emit.isDone) {
      if (_hasPendingDiscovery) {
        final canContinue = await _discoverCameras(emit);
        if (!canContinue) return;
        continue;
      }

      final settled = await _reconcileNativePower(emit);
      if (settled) return;
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
        _emitFailure(emit, failure);
        return false;
    }
  }

  void _emitCapabilities(
    Emitter<CameraState> emit,
    CameraCapabilities capabilities,
  ) {
    final selectedLens = capabilities.availableLenses.contains(state.selectedLens)
        ? state.selectedLens
        : capabilities.preferredLens;
    emit(
      state.copyWith(
        status: _nativeEnabled ? CameraStatus.enabled : CameraStatus.disabled,
        selectedLens: selectedLens,
        availableLenses: capabilities.availableLenses,
        failure: () => null,
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
      if (state.failure == null && state.status != CameraStatus.disabled) {
        emit(
          state.copyWith(
            status: CameraStatus.disabled,
            failure: () => null,
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
            failure: () => null,
          ),
        );
        return true;
      case AppError<void>(:final failure):
        if (_shouldEnable) return false;
        _emitFailure(emit, failure);
        return true;
    }
  }

  Future<bool> _enableSelectedLens(
    Emitter<CameraState> emit,
  ) async {
    final targetLens = state.selectedLens;
    if (_nativeEnabled && _nativeLens == targetLens) {
      if (state.status != CameraStatus.enabled || state.failure != null) {
        emit(
          state.copyWith(
            status: CameraStatus.enabled,
            failure: () => null,
          ),
        );
      }
      return true;
    }

    emit(
      state.copyWith(
        status: _nativeEnabled ? CameraStatus.switching : CameraStatus.initializing,
        failure: () => null,
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
            failure: () => null,
          ),
        );
        return true;
      case AppError<void>(:final failure):
        _nativeEnabled = false;
        _nativeLens = null;
        if (!_shouldEnable || state.selectedLens != targetLens) {
          return false;
        }
        _emitFailure(emit, failure);
        return true;
    }
  }

  void _emitFailure(
    Emitter<CameraState> emit,
    AppFailure failure,
  ) {
    emit(
      state.copyWith(
        status: CameraStatus.failure,
        failure: () => failure,
      ),
    );
  }

  @override
  Future<void> close() async {
    await super.close();
    try {
      await _controller.close();
    } on Exception catch (error, stackTrace) {
      _logger.e(
        'Could not release the camera controller cleanly.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
