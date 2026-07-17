import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:some_camera_with_llm/features/camera/application/models/recorded_video_frame.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/method_channel_recorded_video_frame_source.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS decodes distinct JPEG frames and loops the bundled MP4',
    (tester) async {
      await tester.runAsync<void>(() async {
        final source = MethodChannelRecordedVideoFrameSource(
          assetPath: 'assets/video/pedestrians.mp4',
        );
        try {
          final metadata = _expectSuccess(await source.open());
          final frames = <RecordedVideoFrame>[];
          for (var index = 0; index < 21; index += 1) {
            frames.add(_expectSuccess(await source.nextFrame()));
          }
          final firstFrame = frames.first;
          final secondFrame = frames[1];
          final firstFrameAfterLoop = frames.last;

          expect(metadata.frameWidth, 320);
          expect(metadata.frameHeight, 240);
          expect(metadata.duration.inSeconds, 4);
          _expectJpeg(firstFrame);
          _expectJpeg(secondFrame);
          expect(
            listEquals(firstFrame.encodedImage, secondFrame.encodedImage),
            isFalse,
          );
          expect(firstFrame.sourceFrameNumber, 1);
          expect(firstFrameAfterLoop.sourceFrameNumber, 21);
          expect(firstFrameAfterLoop.presentationTime, firstFrame.presentationTime);
          expect(
            listEquals(
              firstFrame.encodedImage,
              firstFrameAfterLoop.encodedImage,
            ),
            isTrue,
          );
        } finally {
          _expectSuccess(await source.close());
        }
      });
    },
  );
}

void _expectJpeg(RecordedVideoFrame frame) {
  expect(frame.encodedImage.length, greaterThan(4));
  expect(frame.encodedImage.first, 0xFF);
  expect(frame.encodedImage[1], 0xD8);
  expect(frame.encodedImage[frame.encodedImage.length - 2], 0xFF);
  expect(frame.encodedImage.last, 0xD9);
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
