import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// Normalizes model transport, cache, and platform failures.
abstract final class ModelStoreFailureMapper {
  /// Maps [error] to an application-safe failure.
  static AppFailure map(Object error, StackTrace stackTrace) {
    if (error is ModelPreparationCancelledException || error is ModelDownloadCancelledException) {
      return DeviceUnavailableFailure(
        code: 'model_preparation_cancelled',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ModelInsufficientStorageException) {
      return CacheFailure(
        code: 'model_insufficient_storage',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ModelIntegrityException || error is ModelDownloadSizeException) {
      return ValidationFailure(
        code: 'model_integrity',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ModelHttpStatusException) {
      if (error.statusCode == HttpStatus.unauthorized || error.statusCode == HttpStatus.forbidden) {
        return UnauthorizedFailure(
          code: 'model_download_unauthorized',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        );
      }
      if (error.statusCode == HttpStatus.notFound) {
        return NotFoundFailure(
          code: 'model_artifact_not_found',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        );
      }
      return ServerFailure(
        code: 'model_host_response',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TimeoutException) {
      return NetworkFailure(
        code: 'model_download',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is FileSystemException) {
      return CacheFailure(
        code: 'model_cache_io',
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is MissingPluginException || error is PlatformException || error is FormatException) {
      return DeviceUnavailableFailure(
        code: 'model_storage_unavailable',
        message: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return UnexpectedFailure(
      code: 'model_store_unexpected',
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
