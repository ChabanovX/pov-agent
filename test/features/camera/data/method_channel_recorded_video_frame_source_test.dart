import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/recorded_video_frame.dart';
import 'package:pov_agent/features/camera/data/datasources/method_channel_recorded_video_frame_source.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/recorded_video');
  late MethodChannelRecordedVideoFrameSource source;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    source = MethodChannelRecordedVideoFrameSource.withChannel(
      channel,
      assetPath: 'assets/video/pedestrians.mp4',
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('maps native metadata and distinct JPEG frames at the platform boundary', () async {
    var frameNumber = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return switch (call.method) {
          'open' => {
            'width': 320,
            'height': 240,
            'durationMicroseconds': 4000000,
          },
          'nextFrame' => {
            'bytes': Uint8List.fromList([0xFF, 0xD8, ++frameNumber, 0xFF, 0xD9]),
            'frameNumber': frameNumber,
            'presentationTimeMicroseconds': frameNumber * 200000,
          },
          'close' => null,
          _ => throw MissingPluginException(),
        };
      },
    );

    final openResult = await source.open();
    final metadata = (openResult as AppSuccess<RecordedVideoMetadata>).value;
    final firstFrame = (await source.nextFrame() as AppSuccess<RecordedVideoFrame>).value;
    final secondFrame = (await source.nextFrame() as AppSuccess<RecordedVideoFrame>).value;
    final closeResult = await source.close();

    expect(metadata.frameWidth, 320);
    expect(metadata.frameHeight, 240);
    expect(metadata.duration, const Duration(seconds: 4));
    expect(firstFrame.encodedImage, isNot(secondFrame.encodedImage));
    expect(firstFrame.sourceFrameNumber, 1);
    expect(secondFrame.sourceFrameNumber, 2);
    expect(
      () => firstFrame.encodedImage[0] = 0,
      throwsA(isA<UnsupportedError>()),
    );
    expect(closeResult, isA<AppSuccess<void>>());
    expect(
      calls.first.arguments,
      {'assetPath': 'assets/video/pedestrians.mp4'},
    );
    expect(calls.map((call) => call.method), [
      'open',
      'nextFrame',
      'nextFrame',
      'close',
    ]);
  });

  test('normalizes native asset lookup failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        throw PlatformException(
          code: 'VIDEO_ASSET_NOT_FOUND',
          message: 'Missing fixture.',
        );
      },
    );

    final result = await source.open();

    expect(result, isA<AppError<RecordedVideoMetadata>>());
    expect(
      (result as AppError<RecordedVideoMetadata>).failure,
      isA<NotFoundFailure>().having(
        (failure) => failure.code,
        'code',
        'recorded_video_asset_not_found',
      ),
    );
  });

  test('normalizes malformed native frame payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {'bytes': Uint8List(0)},
    );

    final result = await source.nextFrame();

    expect(result, isA<AppError<RecordedVideoFrame>>());
    expect(
      (result as AppError<RecordedVideoFrame>).failure,
      isA<UnexpectedFailure>().having(
        (failure) => failure.code,
        'code',
        'recorded_video_invalid_payload',
      ),
    );
  });
}
