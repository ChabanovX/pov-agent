import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

enum CameraStatus {
  initial,
  initializing,
  enabled,
  disabled,
  switching,
  failure,
}

/// Uses one immutable state because camera availability, user intent, app
/// visibility, lens selection, and native lifecycle change independently.
final class CameraState {
  CameraState({
    this.status = CameraStatus.initial,
    this.selectedLens = CameraLens.back,
    List<CameraLens> availableLenses = const [],
    this.requestedEnabled = true,
    this.surfaceActive = true,
    this.failure,
  }) : availableLenses = List.unmodifiable(availableLenses);

  final CameraStatus status;
  final CameraLens selectedLens;
  final List<CameraLens> availableLenses;
  final bool requestedEnabled;
  final bool surfaceActive;
  final AppFailure? failure;

  bool get canToggleLens => availableLenses.length > 1;

  CameraState copyWith({
    CameraStatus? status,
    CameraLens? selectedLens,
    List<CameraLens>? availableLenses,
    bool? requestedEnabled,
    bool? surfaceActive,
    AppFailure? Function()? failure,
  }) {
    return CameraState(
      status: status ?? this.status,
      selectedLens: selectedLens ?? this.selectedLens,
      availableLenses: availableLenses ?? this.availableLenses,
      requestedEnabled: requestedEnabled ?? this.requestedEnabled,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      failure: failure == null ? this.failure : failure(),
    );
  }
}
