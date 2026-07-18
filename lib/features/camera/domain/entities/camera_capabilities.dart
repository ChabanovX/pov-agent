import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';

/// The camera lenses available to the current device.
final class CameraCapabilities {
  /// Creates immutable capabilities with the supplied preferred lens.
  CameraCapabilities({
    required List<CameraLens> availableLenses,
    required this.preferredLens,
  }) : availableLenses = List.unmodifiable(availableLenses);

  /// The immutable lenses available to the observation session.
  final List<CameraLens> availableLenses;

  /// The lens selected when no current selection is available.
  final CameraLens preferredLens;

  /// Whether the user can switch between multiple lenses.
  bool get canToggleLens => availableLenses.length > 1;
}
