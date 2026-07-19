import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// The native camera power and transition phase.
enum CameraStatus {
  /// No camera initialization has been requested.
  initial,

  /// Camera discovery or native enablement is in progress.
  initializing,

  /// Native observation is enabled.
  enabled,

  /// Native observation is disabled.
  disabled,

  /// A camera lens switch is in progress.
  switching,

  /// Camera discovery or power reconciliation failed.
  failure,
}

/// The observation model preparation phase.
enum ObservationModelStatus {
  /// Model preparation has not started.
  idle,

  /// The model is being resolved or loaded.
  preparing,

  /// The model is being downloaded for its first local use.
  downloading,

  /// The model is ready for inference.
  ready,

  /// Model preparation failed.
  failure,
}

/// The independent camera, model, visibility, and inference state dimensions.
///
/// One immutable value keeps independently changing lifecycle and user-intent
/// dimensions coherent for presentation consumers.
final class CameraState {
  /// Creates an immutable camera state.
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
    this.observationFailure,
  }) : availableLenses = List.unmodifiable(availableLenses),
       detections = List.unmodifiable(detections);

  /// The current native camera phase.
  final CameraStatus status;

  /// The current observation model phase.
  final ObservationModelStatus modelStatus;

  /// The lens selected by user intent or device preference.
  final CameraLens selectedLens;

  /// The immutable lenses discovered for this session.
  final List<CameraLens> availableLenses;

  /// The immutable detections from the latest observed frame.
  final List<Detection> detections;

  /// Whether the user wants observation enabled.
  final bool requestedEnabled;

  /// Whether the surface is visible while the app is foregrounded.
  final bool surfaceActive;

  /// Whether a native or recorded observation surface can be rendered.
  final bool surfaceMounted;

  /// The model download fraction, or `null` outside a known download.
  final double? modelDownloadProgress;

  /// The latest inference diagnostics, or `null` before a valid sample.
  final ObservationDiagnostics? diagnostics;

  /// The latest camera discovery or power failure.
  final AppFailure? cameraFailure;

  /// The latest model preparation failure.
  final AppFailure? modelFailure;

  /// The latest frame acquisition or inference failure.
  final AppFailure? observationFailure;

  /// Whether more than one discovered lens can be selected.
  bool get canToggleLens => availableLenses.length > 1;

  /// The most actionable failure, preferring observation then model then camera.
  AppFailure? get failure => observationFailure ?? modelFailure ?? cameraFailure;

  /// A copy of this state with the supplied values replaced.
  ///
  /// Nullable fields use callbacks so callers can distinguish retaining the
  /// current value from explicitly replacing it with `null`.
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
    AppFailure? Function()? observationFailure,
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
      observationFailure: observationFailure == null ? this.observationFailure : observationFailure(),
    );
  }
}
