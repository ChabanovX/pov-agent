import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// A mapper for YOLO transport, model, and inference failures.
abstract final class YoloFailureMapper {
  /// The normalized failure for [error] and its [stackTrace].
  static AppFailure map(Object error, StackTrace stackTrace) {
    if (error is SocketException || error is HttpException || error is TimeoutException) {
      return NetworkFailure(
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is PlatformException) {
      final searchable = '${error.code} ${error.message}'.toLowerCase();
      if (_containsAny(searchable, const ['permission', 'denied', 'restricted'])) {
        return PermissionDeniedFailure(
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      if (_containsAny(searchable, const ['camera', 'device unavailable', 'not found'])) {
        return DeviceUnavailableFailure(
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      if (_containsAny(searchable, const ['network', 'download', 'offline', 'socket', 'http'])) {
        return NetworkFailure(
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      return UnexpectedFailure(
        code: 'yolo_${error.code}',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is InvalidInputException) {
      return ValidationFailure(
        code: 'invalid_observation_frame',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ModelLoadingException) {
      final message = error.message.toLowerCase();
      if (_containsAny(message, const ['download', 'network', 'socket', 'http', 'offline'])) {
        return NetworkFailure(
          code: 'model_download',
          message: error.message,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      return UnexpectedFailure(
        code: 'model_loading',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ModelNotLoadedException) {
      return UnexpectedFailure(
        code: 'model_not_loaded',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is InferenceException) {
      return UnexpectedFailure(
        code: 'model_inference',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return UnexpectedFailure(
      code: 'yolo_unexpected',
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

bool _containsAny(String value, List<String> candidates) {
  return candidates.any(value.contains);
}
