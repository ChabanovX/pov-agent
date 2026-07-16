import 'package:some_camera_with_llm/features/camera/domain/entities/normalized_box.dart';

/// One model-owned object detection without plugin or wire-format types.
final class Detection {
  const Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.box,
  }) : assert(
         confidence >= 0 && confidence <= 1,
         'Detection confidence must be normalized.',
       );

  final int classId;
  final String label;
  final double confidence;
  final NormalizedBox box;
}
