import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// Runtime updates emitted by the native observation adapter.
sealed class ObservationEvent {
  /// Creates an observation runtime event.
  const ObservationEvent();
}

/// An event indicating that model preparation has started.
final class ObservationModelPreparing extends ObservationEvent {
  /// Creates a model-preparing event.
  const ObservationModelPreparing();
}

/// An event reporting first-load model download progress.
final class ObservationModelDownloadProgressed extends ObservationEvent {
  /// Creates a model-download event with normalized [progress].
  const ObservationModelDownloadProgressed(this.progress);

  /// The completed download fraction from zero to one.
  final double progress;
}

/// An event indicating that the model can perform inference.
final class ObservationModelReady extends ObservationEvent {
  /// Creates a model-ready event.
  const ObservationModelReady();
}

/// An event containing the detections for one observed frame.
final class ObservationDetectionsUpdated extends ObservationEvent {
  /// Creates an immutable detection update observed at [observedAt].
  ObservationDetectionsUpdated({
    required List<Detection> detections,
    required this.observedAt,
  }) : detections = List.unmodifiable(detections);

  /// The immutable detections for the observed frame.
  final List<Detection> detections;

  /// The UTC time at which the frame was observed.
  final DateTime observedAt;
}

/// An event containing the latest inference diagnostics.
final class ObservationDiagnosticsUpdated extends ObservationEvent {
  /// Creates a diagnostics update containing [diagnostics].
  const ObservationDiagnosticsUpdated(this.diagnostics);

  /// The latest inference diagnostics.
  final ObservationDiagnostics diagnostics;
}

/// An event reporting a model preparation or live-runtime failure.
final class ObservationFailed extends ObservationEvent {
  /// Creates an observation failure event containing [failure].
  const ObservationFailed(this.failure);

  /// The normalized model or live-runtime failure.
  final AppFailure failure;
}

/// An event reporting frame inference failure after the model is ready.
final class ObservationInferenceFailed extends ObservationEvent {
  /// Creates an inference failure event containing [failure].
  const ObservationInferenceFailed(this.failure);

  /// The normalized frame inference failure.
  final AppFailure failure;
}
