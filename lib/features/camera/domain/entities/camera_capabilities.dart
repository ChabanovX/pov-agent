import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';

/// Describes the camera lenses available to the current device.
final class CameraCapabilities {
  CameraCapabilities({
    required List<CameraLens> availableLenses,
    required this.preferredLens,
  }) : availableLenses = List.unmodifiable(availableLenses);

  final List<CameraLens> availableLenses;
  final CameraLens preferredLens;

  bool get canToggleLens => availableLenses.length > 1;
}
