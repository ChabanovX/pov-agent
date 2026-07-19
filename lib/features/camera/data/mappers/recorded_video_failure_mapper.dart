import 'package:flutter/services.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// A mapper for recorded-video channel failures at the data boundary.
abstract final class RecordedVideoFailureMapper {
  /// The normalized failure for [error] and its [stackTrace].
  static AppFailure map(Object error, StackTrace stackTrace) {
    if (error is MissingPluginException) {
      return DeviceUnavailableFailure(
        code: 'recorded_video_decoder_unavailable',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is PlatformException) {
      return switch (error.code) {
        'VIDEO_ASSET_NOT_FOUND' => NotFoundFailure(
          code: 'recorded_video_asset_not_found',
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        ),
        'VIDEO_INVALID_ARGUMENTS' || 'VIDEO_NO_TRACK' || 'VIDEO_EMPTY' => ValidationFailure(
          code: 'invalid_recorded_video',
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        ),
        'VIDEO_READER_FAILED' || 'VIDEO_FRAME_DECODE_FAILED' => DeviceUnavailableFailure(
          code: 'recorded_video_decoder_failed',
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        ),
        _ => UnexpectedFailure(
          code: 'recorded_video_${error.code.toLowerCase()}',
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        ),
      };
    }

    if (error is FormatException) {
      return UnexpectedFailure(
        code: 'recorded_video_invalid_payload',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return UnexpectedFailure(
      code: 'recorded_video_unexpected',
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
