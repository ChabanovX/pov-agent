import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';

void main() {
  test('maps valid native detections into owned normalized domain values', () {
    final detections = YoloResultMapper.detectionsFromRaw([
      {
        'classIndex': 5,
        'className': 'bus',
        'confidence': 0.91,
        'normalizedBox': {
          'left': 0.1,
          'top': 0.2,
          'right': 0.8,
          'bottom': 0.9,
        },
      },
    ]);

    expect(detections, hasLength(1));
    expect(detections.single.classId, 5);
    expect(detections.single.label, 'bus');
    expect(detections.single.confidence, 0.91);
    expect(detections.single.box.left, 0.1);
    expect(detections.single.box.bottom, 0.9);
  });

  test('clamps finite native values and ignores malformed detections', () {
    final detections = YoloResultMapper.detectionsFromRaw([
      {
        'classIndex': 0,
        'className': 'person',
        'confidence': 1.2,
        'normalizedBox': {
          'left': -0.2,
          'top': 0.1,
          'right': 1.4,
          'bottom': 0.8,
        },
      },
      {
        'classIndex': 2,
        'className': 'car',
        'confidence': 0.8,
        'normalizedBox': {
          'left': 0.8,
          'top': 0.1,
          'right': 0.2,
          'bottom': 0.8,
        },
      },
      {
        'classIndex': double.infinity,
        'className': 'car',
        'confidence': 0.8,
        'normalizedBox': {
          'left': 0.1,
          'top': 0.1,
          'right': 0.8,
          'bottom': 0.8,
        },
      },
      {
        'classIndex': 2,
        'className': 'car',
        'confidence': double.nan,
        'normalizedBox': {
          'left': 0.1,
          'top': 0.1,
          'right': 0.8,
          'bottom': 0.8,
        },
      },
    ]);

    expect(detections, hasLength(1));
    expect(detections.single.confidence, 1);
    expect(detections.single.box.left, 0);
    expect(detections.single.box.right, 1);
  });

  test('uses total processing time when native inference time is absent', () {
    final sampledAt = DateTime.utc(2026, 7, 16, 12);

    final diagnostics = YoloResultMapper.diagnosticsFromRaw(
      {
        'fps': 18.5,
        'processingTimeMs': 42.0,
        'inferenceMs': 0.0,
        'frameNumber': 7,
      },
      sampledAt: sampledAt,
    );

    expect(diagnostics.framesPerSecond, 18.5);
    expect(diagnostics.inferenceTimeMs, 42);
    expect(diagnostics.frameNumber, 7);
    expect(diagnostics.sampledAt, sampledAt);
  });

  test('normalizes non-finite native diagnostics instead of throwing', () {
    final diagnostics = YoloResultMapper.diagnosticsFromRaw(
      {
        'fps': double.nan,
        'processingTimeMs': double.infinity,
        'inferenceMs': double.negativeInfinity,
        'frameNumber': double.infinity,
      },
      sampledAt: DateTime.utc(2026, 7, 16, 12),
    );

    expect(diagnostics.framesPerSecond, 0);
    expect(diagnostics.inferenceTimeMs, 0);
    expect(diagnostics.processingTimeMs, 0);
    expect(diagnostics.frameNumber, 0);
  });
}
