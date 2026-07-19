import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';

/// One model-owned object detection without plugin or wire-format types.
final class Detection {
  /// Creates a detection with normalized [confidence] and [box] values.
  const Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.box,
  }) : assert(
         confidence >= 0 && confidence <= 1,
         'Detection confidence must be normalized.',
       );

  /// The model's numeric class identifier.
  final int classId;

  /// The model's human-readable class label.
  final String label;

  /// The normalized model confidence from zero to one.
  final double confidence;

  /// The normalized bounds of the detected object.
  final NormalizedBox box;
}
