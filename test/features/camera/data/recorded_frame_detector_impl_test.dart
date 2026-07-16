import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/repositories/recorded_frame_detector_impl.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_snapshot.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  late _FakeRecordedFrameInference inference;
  late RecordedFrameDetectorImpl detector;

  setUp(() {
    inference = _FakeRecordedFrameInference();
    detector = RecordedFrameDetectorImpl(
      inference,
      const YoloResultMapper(),
      const YoloFailureMapper(),
      utcNow: () => DateTime.utc(2026, 7, 16, 12),
    );
  });

  tearDown(() => detector.close());

  test('maps raw plugin transport output at the repository boundary', () async {
    inference.result = {
      'detections': [
        {
          'classIndex': 0,
          'className': 'person',
          'confidence': 0.88,
          'normalizedBox': {
            'left': 0.2,
            'top': 0.1,
            'right': 0.6,
            'bottom': 0.9,
          },
        },
      ],
      'processingTimeMs': 31.5,
    };

    expect(await detector.load(), isA<AppSuccess<void>>());
    final result = await detector.detect(Uint8List.fromList([1, 2, 3]));
    final snapshot = (result as AppSuccess<ObservationSnapshot>).value;

    expect(inference.loadCalls, 1);
    expect(inference.predictCalls, 1);
    expect(snapshot.detections.single.label, 'person');
    expect(snapshot.processingTimeMs, 31.5);
    expect(snapshot.observedAt, DateTime.utc(2026, 7, 16, 12));
  });

  test('normalizes native invalid-input failures', () async {
    inference.predictError = InvalidInputException('Corrupt JPEG bytes.');

    final result = await detector.detect(Uint8List(0));

    expect(result, isA<AppError<ObservationSnapshot>>());
    expect(
      (result as AppError<ObservationSnapshot>).failure,
      isA<ValidationFailure>(),
    );
  });
}

final class _FakeRecordedFrameInference implements RecordedFrameInference {
  Map<String, dynamic> result = const {
    'detections': <Map<String, dynamic>>[],
    'processingTimeMs': 0.0,
  };
  Exception? loadError;
  Exception? predictError;
  int loadCalls = 0;
  int predictCalls = 0;
  int closeCalls = 0;

  @override
  Future<void> load() async {
    loadCalls += 1;
    final error = loadError;
    if (error != null) throw error;
  }

  @override
  Future<Map<String, dynamic>> predict(Uint8List encodedImage) async {
    predictCalls += 1;
    final error = predictError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}
