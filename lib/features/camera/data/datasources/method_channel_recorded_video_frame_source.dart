import 'package:flutter/services.dart';
import 'package:some_camera_with_llm/features/camera/application/models/recorded_video_frame.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/recorded_video_frame_source.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/recorded_video_failure_mapper.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

const _recordedVideoChannelName = 'some_camera_with_llm/recorded_video';

/// A bundled-video decoder backed by the app-owned iOS platform channel.
final class MethodChannelRecordedVideoFrameSource implements RecordedVideoFrameSource {
  /// Creates a source using the production recorded-video platform channel.
  factory MethodChannelRecordedVideoFrameSource({
    required String assetPath,
  }) {
    return MethodChannelRecordedVideoFrameSource.withChannel(
      const MethodChannel(_recordedVideoChannelName),
      assetPath: assetPath,
    );
  }

  /// Creates a source with an injectable platform [channel].
  ///
  /// This constructor supports deterministic platform-boundary tests.
  MethodChannelRecordedVideoFrameSource.withChannel(
    MethodChannel channel, {
    required this.assetPath,
  }) : _channel = channel;

  /// The bundled Flutter asset decoded by the native video reader.
  final String assetPath;
  final MethodChannel _channel;

  @override
  Future<AppResult<RecordedVideoMetadata>> open() {
    return _mapOperation(() async {
      final payload = await _channel.invokeMethod<Object?>('open', {
        'assetPath': assetPath,
      });
      final map = _requireMap(payload, operation: 'open');
      final frameWidth = _requirePositiveInt(map, 'width');
      final frameHeight = _requirePositiveInt(map, 'height');
      final durationMicroseconds = _requireNonNegativeInt(
        map,
        'durationMicroseconds',
      );
      return RecordedVideoMetadata(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        duration: Duration(microseconds: durationMicroseconds),
      );
    });
  }

  @override
  Future<AppResult<RecordedVideoFrame>> nextFrame() {
    return _mapOperation(() async {
      final payload = await _channel.invokeMethod<Object?>('nextFrame');
      final map = _requireMap(payload, operation: 'nextFrame');
      final bytes = map['bytes'];
      if (bytes is! Uint8List || bytes.isEmpty) {
        throw const FormatException(
          'Recorded video nextFrame returned empty or invalid JPEG bytes.',
        );
      }
      return RecordedVideoFrame(
        encodedImage: bytes,
        sourceFrameNumber: _requireNonNegativeInt(map, 'frameNumber'),
        presentationTime: Duration(
          microseconds: _requireNonNegativeInt(
            map,
            'presentationTimeMicroseconds',
          ),
        ),
      );
    });
  }

  @override
  Future<AppResult<void>> close() {
    return _mapOperation(() async {
      await _channel.invokeMethod<void>('close');
    });
  }

  Future<AppResult<T>> _mapOperation<T>(Future<T> Function() operation) async {
    try {
      return AppSuccess(await operation());
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(RecordedVideoFailureMapper.map(error, stackTrace));
    }
  }
}

Map<Object?, Object?> _requireMap(Object? payload, {required String operation}) {
  if (payload case final Map<Object?, Object?> map) return map;
  throw FormatException(
    'Recorded video $operation returned an invalid platform payload.',
  );
}

int _requirePositiveInt(Map<Object?, Object?> map, String key) {
  final value = _requireNonNegativeInt(map, key);
  if (value > 0) return value;
  throw FormatException('Recorded video payload field "$key" must be positive.');
}

int _requireNonNegativeInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is int && value >= 0) return value;
  throw FormatException(
    'Recorded video payload field "$key" must be a non-negative integer.',
  );
}
