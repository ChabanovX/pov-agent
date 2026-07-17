import 'package:some_camera_with_llm/features/camera/domain/entities/detection.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

/// Runtime updates emitted by the native observation adapter.
sealed class ObservationEvent {
  const ObservationEvent();
}

final class ObservationModelPreparing extends ObservationEvent {
  const ObservationModelPreparing();
}

final class ObservationModelDownloadProgressed extends ObservationEvent {
  const ObservationModelDownloadProgressed(this.progress);

  final double progress;
}

final class ObservationModelReady extends ObservationEvent {
  const ObservationModelReady();
}

final class ObservationDetectionsUpdated extends ObservationEvent {
  ObservationDetectionsUpdated({
    required List<Detection> detections,
    required this.observedAt,
  }) : detections = List.unmodifiable(detections);

  final List<Detection> detections;
  final DateTime observedAt;
}

final class ObservationDiagnosticsUpdated extends ObservationEvent {
  const ObservationDiagnosticsUpdated(this.diagnostics);

  final ObservationDiagnostics diagnostics;
}

final class ObservationFailed extends ObservationEvent {
  const ObservationFailed(this.failure);

  final AppFailure failure;
}

/// Reports frame inference failure after the model has loaded successfully.
final class ObservationInferenceFailed extends ObservationEvent {
  const ObservationInferenceFailed(this.failure);

  final AppFailure failure;
}
