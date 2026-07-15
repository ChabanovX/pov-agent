import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:some_camera_with_llm/core/logging/app_logger.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/camera_controller.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_state.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// Coordinates user camera intent with tab and application visibility.
///
/// Responsibilities:
/// - Discover available front and rear lenses.
/// - Serialize native enable, disable, and lens-switch operations.
/// - Preserve manual power preference across visibility suspension.
/// - Normalize camera results into presentation state.
final class CameraCubit extends Cubit<CameraState> {
  CameraCubit(
    this._controller, {
    bool initiallySurfaceActive = true,
  }) : super(CameraState(surfaceActive: initiallySurfaceActive));

  static final AppLogger _logger = AppLogger('CameraCubit');

  final CameraController _controller;

  // Concurrency policy: serialize every public command so native controller
  // initialization, stream shutdown, disposal, and lens replacement never overlap.
  Future<void> _operation = Future.value();

  Future<void> init() => _enqueue(_initialize);

  Future<void> enableCamera() {
    return _enqueue(() async {
      emit(
        state.copyWith(
          requestedEnabled: true,
          failure: () => null,
        ),
      );
      if (state.availableLenses.isEmpty) {
        await _initialize();
      } else {
        await _reconcilePower();
      }
    });
  }

  Future<void> disableCamera() {
    return _enqueue(() async {
      emit(
        state.copyWith(
          requestedEnabled: false,
          failure: () => null,
        ),
      );
      await _reconcilePower();
    });
  }

  Future<void> toggleCamera() {
    return _enqueue(() async {
      if (!state.canToggleLens) return;

      final nextLens = state.selectedLens == CameraLens.back ? CameraLens.front : CameraLens.back;
      if (!state.requestedEnabled || !state.surfaceActive) {
        emit(
          state.copyWith(
            status: CameraStatus.disabled,
            selectedLens: nextLens,
            failure: () => null,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: CameraStatus.switching,
          selectedLens: nextLens,
          failure: () => null,
        ),
      );
      final result = await _controller.enable(nextLens);
      if (isClosed) return;
      _emitCommandResult(result, successStatus: CameraStatus.enabled);
    });
  }

  Future<void> setSurfaceActive({required bool active}) {
    return _enqueue(() async {
      if (state.surfaceActive == active) return;
      emit(state.copyWith(surfaceActive: active));

      if (active && state.status == CameraStatus.initial) {
        await _initialize();
      } else {
        await _reconcilePower();
      }
    });
  }

  Future<void> _initialize() async {
    emit(
      state.copyWith(
        status: CameraStatus.initializing,
        failure: () => null,
      ),
    );
    final result = await _controller.init();
    if (isClosed) return;

    switch (result) {
      case AppSuccess(value: final capabilities):
        _emitCapabilities(capabilities);
        await _reconcilePower();
      case AppError(:final failure):
        _emitFailure(failure);
    }
  }

  void _emitCapabilities(CameraCapabilities capabilities) {
    final selectedLens = capabilities.availableLenses.contains(state.selectedLens)
        ? state.selectedLens
        : capabilities.preferredLens;
    emit(
      state.copyWith(
        status: CameraStatus.disabled,
        selectedLens: selectedLens,
        availableLenses: capabilities.availableLenses,
        failure: () => null,
      ),
    );
  }

  Future<void> _reconcilePower() async {
    final shouldEnable = state.requestedEnabled && state.surfaceActive;
    if (shouldEnable) {
      if (state.status == CameraStatus.enabled) return;
      emit(
        state.copyWith(
          status: CameraStatus.initializing,
          failure: () => null,
        ),
      );
      final result = await _controller.enable(state.selectedLens);
      if (isClosed) return;
      _emitCommandResult(result, successStatus: CameraStatus.enabled);
      return;
    }

    if (state.status == CameraStatus.disabled || state.status == CameraStatus.initial) {
      emit(
        state.copyWith(
          status: CameraStatus.disabled,
          failure: () => null,
        ),
      );
      return;
    }

    final result = await _controller.disable();
    if (isClosed) return;
    _emitCommandResult(result, successStatus: CameraStatus.disabled);
  }

  void _emitCommandResult(
    AppResult<void> result, {
    required CameraStatus successStatus,
  }) {
    switch (result) {
      case AppSuccess<void>():
        emit(
          state.copyWith(
            status: successStatus,
            failure: () => null,
          ),
        );
      case AppError<void>(:final failure):
        _emitFailure(failure);
    }
  }

  void _emitFailure(AppFailure failure) {
    emit(
      state.copyWith(
        status: CameraStatus.failure,
        failure: () => failure,
      ),
    );
  }

  Future<void> _enqueue(Future<void> Function() command) {
    final result = _operation.then((_) async {
      if (isClosed) return;
      await command();
    });
    _operation = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.e(
          'Serialized camera command failed unexpectedly.',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    return result;
  }

  @override
  Future<void> close() async {
    await _operation;
    try {
      await _controller.close();
    } on Exception catch (error, stackTrace) {
      _logger.e(
        'Could not release the camera controller cleanly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      await super.close();
    }
  }
}
