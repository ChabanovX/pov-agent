import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:some_camera_with_llm/core/logging/app_logger.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:some_camera_with_llm/features/camera/data/debug/recorded_bus_fixture.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/repositories/recorded_frame_detector_impl.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';
import 'package:ultralytics_yolo/core/yolo_model_resolver.dart';

const _modelId = 'yolo26n';
const _runRecordedYoloReplayTest = bool.fromEnvironment(
  'RUN_RECORDED_YOLO_REPLAY_TEST',
);
final _logger = AppLogger('RecordedYoloReplayTest');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real yolo26n recognizes recorded frames and reopens from cache',
    (tester) async {
      await tester.runAsync<void>(() async {
        final frames = recordedBusFixture().frames;
        expect(frames, hasLength(3));
        expect(frames.first, isNotEmpty);

        final firstDetector = _createDetector();
        final labels = <String>{};
        try {
          _expectSuccess(await firstDetector.load());
          for (final frame in frames) {
            final snapshot = _expectSuccess(
              await firstDetector.detect(frame),
            );
            labels.addAll(snapshot.detections.map((item) => item.label));
          }
        } finally {
          await firstDetector.close();
        }

        _logger.i('Recorded sequence labels: ${labels.toList()..sort()}');
        expect(labels, contains('person'));
        expect(
          await YOLOModelResolver.isOfficialModelAvailableLocally(_modelId),
          isTrue,
        );

        // A fresh runtime must reuse the extracted model and emit no download
        // progress, which is the offline relaunch contract for Milestone 1.
        final cacheDownloadEvents = <DownloadProgress>[];
        final progressSubscription = YOLOModelManager.downloadProgress
            .where((event) => event.modelId == _modelId)
            .listen(cacheDownloadEvents.add);
        final cachedDetector = _createDetector();
        try {
          _expectSuccess(await cachedDetector.load());
          final cachedSnapshot = _expectSuccess(
            await cachedDetector.detect(frames.first),
          );
          expect(
            cachedSnapshot.detections.map((item) => item.label),
            contains('person'),
          );
          expect(cacheDownloadEvents, isEmpty);
        } finally {
          await cachedDetector.close();
          await progressSubscription.cancel();
        }
      });
    },
    skip: !_runRecordedYoloReplayTest,
    timeout: Timeout.none,
  );
}

RecordedFrameDetectorImpl _createDetector() {
  return RecordedFrameDetectorImpl(
    UltralyticsRecordedFrameInference(),
    const YoloResultMapper(),
    const YoloFailureMapper(),
  );
}

T _expectSuccess<T>(AppResult<T> result) {
  return result.fold(
    onSuccess: (value) => value,
    onFailure: _failWithFailure,
  );
}

Never _failWithFailure(AppFailure failure) {
  fail(
    'Expected success, got ${failure.runtimeType}(${failure.code}): '
    '${failure.message}',
  );
}
