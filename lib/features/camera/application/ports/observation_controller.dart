import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A controller for one observation session without exposed plugin types.
abstract interface class ObservationController {
  /// Broadcast runtime events for model state, detections, diagnostics, and
  /// failures.
  ///
  /// Multiple application consumers observe the same session, so
  /// implementations must return a stream whose [Stream.isBroadcast] is true.
  /// Events must also belong to the current observation epoch: callbacks from
  /// superseded surfaces, retries, or sources are discarded before emission.
  Stream<ObservationEvent> get events;

  /// Initializes observation resources and reports available camera lenses.
  Future<AppResult<CameraCapabilities>> init();

  /// Enables observation with [lens].
  Future<AppResult<void>> enable(CameraLens lens);

  /// Suspends observation while retaining reusable resources.
  ///
  /// Completion means no frame acquisition or inference operation remains in
  /// flight, so an app-level lifecycle coordinator may safely release another
  /// native compute runtime afterwards.
  Future<AppResult<void>> disable();

  /// Restarts model preparation after a model failure.
  Future<AppResult<void>> retryModel();

  /// Restarts frame acquisition or inference without reloading the model.
  Future<AppResult<void>> retryObservation();

  /// Releases all observation resources and completes event streams.
  Future<void> close();
}
