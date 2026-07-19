import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A controller for one observation session without exposed plugin types.
abstract interface class ObservationController {
  /// Runtime events for model state, detections, diagnostics, and failures.
  Stream<ObservationEvent> get events;

  /// Initializes observation resources and reports available camera lenses.
  Future<AppResult<CameraCapabilities>> init();

  /// Enables observation with [lens].
  Future<AppResult<void>> enable(CameraLens lens);

  /// Suspends observation while retaining reusable resources.
  Future<AppResult<void>> disable();

  /// Restarts model preparation after a model failure.
  Future<AppResult<void>> retryModel();

  /// Restarts frame acquisition or inference without reloading the model.
  Future<AppResult<void>> retryObservation();

  /// Releases all observation resources and completes event streams.
  Future<void> close();
}
