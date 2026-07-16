import 'package:some_camera_with_llm/features/camera/domain/entities/detection.dart';

/// Detection output for one encoded or live observation frame.
final class ObservationSnapshot {
  ObservationSnapshot({
    required List<Detection> detections,
    required this.processingTimeMs,
    required this.observedAt,
  }) : detections = List.unmodifiable(detections);

  final List<Detection> detections;
  final double processingTimeMs;
  final DateTime observedAt;
}
