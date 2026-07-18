import 'package:some_camera_with_llm/features/camera/data/dto/yolo_detection_dto.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/detection.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/normalized_box.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_snapshot.dart';

/// A mapper from YOLO plugin payloads to owned domain values.
final class YoloResultMapper {
  /// Creates a YOLO result mapper.
  const YoloResultMapper();

  /// Valid detections mapped from [raw], excluding malformed entries.
  List<Detection> detectionsFromRaw(Iterable<Map<dynamic, dynamic>> raw) {
    return raw
        .map(YoloDetectionDto.tryFromMap)
        .whereType<YoloDetectionDto>()
        .map(_detectionFromDto)
        .toList(growable: false);
  }

  /// A normalized diagnostics sample mapped from [raw].
  ///
  /// Missing, negative, or non-finite metrics become zero. Total processing
  /// time is used when the native inference duration is unavailable.
  ObservationDiagnostics diagnosticsFromRaw(
    Map<String, dynamic> raw, {
    required DateTime sampledAt,
  }) {
    final processingTimeMs = _nonNegativeDouble(raw['processingTimeMs']);
    final nativeInferenceTimeMs = _nonNegativeDouble(raw['inferenceMs']);
    return ObservationDiagnostics(
      framesPerSecond: _nonNegativeDouble(raw['fps']),
      inferenceTimeMs: nativeInferenceTimeMs > 0 ? nativeInferenceTimeMs : processingTimeMs,
      processingTimeMs: processingTimeMs,
      frameNumber: _nonNegativeInt(raw['frameNumber']),
      sampledAt: sampledAt,
    );
  }

  /// An owned inference snapshot mapped from [raw] at [observedAt].
  ObservationSnapshot snapshotFromRaw(
    Map<String, dynamic> raw, {
    required DateTime observedAt,
  }) {
    final rawDetections = raw['detections'];
    final detections = rawDetections is List
        ? detectionsFromRaw(
            rawDetections.whereType<Map<dynamic, dynamic>>(),
          )
        : const <Detection>[];
    return ObservationSnapshot(
      detections: detections,
      processingTimeMs: _nonNegativeDouble(raw['processingTimeMs']),
      observedAt: observedAt,
    );
  }
}

Detection _detectionFromDto(YoloDetectionDto dto) {
  return Detection(
    classId: dto.classId,
    label: dto.label,
    confidence: dto.confidence,
    box: NormalizedBox(
      left: dto.left,
      top: dto.top,
      right: dto.right,
      bottom: dto.bottom,
    ),
  );
}

double _nonNegativeDouble(Object? value) {
  if (value is! num || !value.isFinite) return 0;
  return value.toDouble().clamp(0, double.infinity).toDouble();
}

int _nonNegativeInt(Object? value) {
  if (value is! num || !value.isFinite) return 0;
  return value.toInt().clamp(0, 0x7FFFFFFF);
}
