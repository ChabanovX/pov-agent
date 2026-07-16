import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/detection.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

enum CameraStatus {
  initial,
  initializing,
  enabled,
  disabled,
  switching,
  failure,
}

enum ObservationModelStatus {
  idle,
  preparing,
  downloading,
  ready,
  failure,
}

/// Uses one immutable state because camera availability, user intent, app
/// visibility, model loading, detections, and native lifecycle change
/// independently.
final class CameraState {
  CameraState({
    this.status = CameraStatus.initial,
    this.modelStatus = ObservationModelStatus.idle,
    this.selectedLens = CameraLens.back,
    List<CameraLens> availableLenses = const [],
    List<Detection> detections = const [],
    this.requestedEnabled = true,
    this.surfaceActive = true,
    this.surfaceMounted = false,
    this.modelDownloadProgress,
    this.diagnostics,
    this.cameraFailure,
    this.modelFailure,
  }) : availableLenses = List.unmodifiable(availableLenses),
       detections = List.unmodifiable(detections);

  final CameraStatus status;
  final ObservationModelStatus modelStatus;
  final CameraLens selectedLens;
  final List<CameraLens> availableLenses;
  final List<Detection> detections;
  final bool requestedEnabled;
  final bool surfaceActive;
  final bool surfaceMounted;
  final double? modelDownloadProgress;
  final ObservationDiagnostics? diagnostics;
  final AppFailure? cameraFailure;
  final AppFailure? modelFailure;

  bool get canToggleLens => availableLenses.length > 1;

  AppFailure? get failure => modelFailure ?? cameraFailure;

  CameraState copyWith({
    CameraStatus? status,
    ObservationModelStatus? modelStatus,
    CameraLens? selectedLens,
    List<CameraLens>? availableLenses,
    List<Detection>? detections,
    bool? requestedEnabled,
    bool? surfaceActive,
    bool? surfaceMounted,
    double? Function()? modelDownloadProgress,
    ObservationDiagnostics? Function()? diagnostics,
    AppFailure? Function()? cameraFailure,
    AppFailure? Function()? modelFailure,
  }) {
    return CameraState(
      status: status ?? this.status,
      modelStatus: modelStatus ?? this.modelStatus,
      selectedLens: selectedLens ?? this.selectedLens,
      availableLenses: availableLenses ?? this.availableLenses,
      detections: detections ?? this.detections,
      requestedEnabled: requestedEnabled ?? this.requestedEnabled,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      surfaceMounted: surfaceMounted ?? this.surfaceMounted,
      modelDownloadProgress: modelDownloadProgress == null ? this.modelDownloadProgress : modelDownloadProgress(),
      diagnostics: diagnostics == null ? this.diagnostics : diagnostics(),
      cameraFailure: cameraFailure == null ? this.cameraFailure : cameraFailure(),
      modelFailure: modelFailure == null ? this.modelFailure : modelFailure(),
    );
  }
}
