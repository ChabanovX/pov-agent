import 'package:flutter/services.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/ffi/sherpa_online_recognition_worker.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// Normalizes microphone and native-ASR failures before they leave data.
abstract final class SpeechRecognitionFailureMapper {
  /// Maps [error] using [fallbackCode] when no narrower category applies.
  static AppFailure map(
    Object error,
    StackTrace stackTrace, {
    required String fallbackCode,
  }) {
    if (error case final MicrophoneCaptureException captureFailure) {
      return DeviceUnavailableFailure(
        code: captureFailure.code,
        message: captureFailure.message,
        cause: captureFailure.cause ?? captureFailure,
        stackTrace: stackTrace,
      );
    }

    if (error case final AsrWorkerException workerFailure) {
      return UnexpectedFailure(
        code: workerFailure.code,
        message: workerFailure.message,
        cause: workerFailure,
        stackTrace: stackTrace,
      );
    }

    if (error case final PlatformException platformFailure) {
      final searchable = '${platformFailure.code} ${platformFailure.message}'.toLowerCase();
      if (_containsAny(searchable, const [
        'permission',
        'denied',
        'restricted',
      ])) {
        return PermissionDeniedFailure(
          code: 'microphone_permission_denied',
          message: platformFailure.message,
          cause: platformFailure,
          stackTrace: stackTrace,
        );
      }
      return DeviceUnavailableFailure(
        code: 'microphone_capture_platform_failure',
        message: platformFailure.message,
        cause: platformFailure,
        stackTrace: stackTrace,
      );
    }

    if (error is UnsupportedError) {
      return DeviceUnavailableFailure(
        code: 'microphone_pcm16_unsupported',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return UnexpectedFailure(
      code: fallbackCode,
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

bool _containsAny(String value, List<String> candidates) {
  return candidates.any(value.contains);
}
