import 'package:pov_agent/features/camera/domain/entities/detection.dart';

/// Detection output for one encoded or live observation frame.
final class ObservationSnapshot {
  /// Creates an immutable inference snapshot observed at [observedAt].
  ObservationSnapshot({
    required List<Detection> detections,
    required this.processingTimeMs,
    required this.observedAt,
  }) : detections = List.unmodifiable(detections);

  /// The immutable detections produced for one frame.
  final List<Detection> detections;

  /// The total frame processing duration in milliseconds.
  final double processingTimeMs;

  /// The UTC time at which the frame was observed.
  final DateTime observedAt;
}
