import 'dart:async';

import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Decides whether a primary failure is safe to repeat through fallback speech.
typedef SpeechFallbackPolicy = bool Function(AppFailure failure);

/// Uses a local speech runtime first and a technical fallback when safe.
///
/// Fallback is evaluated independently for each utterance. Stop invalidates the
/// active attempt before awaiting either backend, so a late primary failure can
/// never start fallback speech after the caller has asked for silence.
final class FallbackSpeechSynthesizer implements SpeechSynthesizer {
  /// Creates a process-owned speech coordinator.
  FallbackSpeechSynthesizer({
    required SpeechSynthesizer primary,
    required SpeechSynthesizer fallback,
    required SpeechFallbackPolicy shouldFallback,
  }) : this._(primary, fallback, shouldFallback);

  FallbackSpeechSynthesizer._(
    this._primary,
    this._fallback,
    this._shouldFallback,
  );

  static final AppLogger _logger = AppLogger(
    'FallbackSpeechSynthesizer',
  );

  final SpeechSynthesizer _primary;
  final SpeechSynthesizer _fallback;
  final SpeechFallbackPolicy _shouldFallback;

  _FallbackSpeechOperation? _active;
  Future<AppResult<void>>? _stopTask;
  Future<AppResult<void>>? _closeTask;
  var _closed = false;

  @override
  Future<AppResult<void>> speak(String text) {
    if (_closed) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'speech_coordinator_closed'),
        ),
      );
    }
    if (_active != null || _stopTask != null) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'speech_coordinator_busy'),
        ),
      );
    }

    final operation = _FallbackSpeechOperation();
    _active = operation;
    unawaited(_run(operation, text));
    return operation.completion.future;
  }

  Future<void> _run(_FallbackSpeechOperation operation, String text) async {
    AppResult<void> result;
    try {
      final primaryResult = await _primary.speak(text);
      if (operation.cancelled || _closed) {
        result = const AppSuccess<void>(null);
      } else if (primaryResult case AppError<void>(:final failure) when _shouldFallback(failure)) {
        _logger.w(
          'Local speech failed before playback; using the system fallback.',
          error: failure.cause ?? failure.code,
          stackTrace: failure.stackTrace,
        );
        result = await _fallback.speak(text);
      } else {
        result = primaryResult;
      }
    } on Object catch (error, stackTrace) {
      result = AppError(
        UnexpectedFailure(
          code: 'speech_coordinator_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    if (operation.cancelled || _closed) {
      result = const AppSuccess<void>(null);
    }
    if (identical(_active, operation)) _active = null;
    if (!operation.completion.isCompleted) {
      operation.completion.complete(result);
    }
  }

  @override
  Future<AppResult<void>> stop() {
    final existing = _stopTask;
    if (existing != null) return existing;

    late final Future<AppResult<void>> task;
    task = _stopOnce().whenComplete(() {
      if (identical(_stopTask, task)) _stopTask = null;
    });
    _stopTask = task;
    return task;
  }

  Future<AppResult<void>> _stopOnce() async {
    final operation = _active;
    operation?.cancelled = true;
    final results = await Future.wait<AppResult<void>>([
      _primary.stop(),
      _fallback.stop(),
    ]);
    if (operation != null) await operation.completion.future;
    return _firstFailureOrSuccess(results);
  }

  @override
  Future<AppResult<void>> close() {
    final existing = _closeTask;
    if (existing != null) return existing;

    _closed = true;
    _active?.cancelled = true;
    late final Future<AppResult<void>> task;
    task = _closeOnce().then((result) {
      if (result is AppError<void> && identical(_closeTask, task)) {
        // Both backend instances remain referenced, so a later close can retry
        // whichever native owner failed to release.
        _closeTask = null;
      }
      return result;
    });
    _closeTask = task;
    return task;
  }

  Future<AppResult<void>> _closeOnce() async {
    final operation = _active;
    final results = await Future.wait<AppResult<void>>([
      _primary.close(),
      _fallback.close(),
    ]);
    if (operation != null) await operation.completion.future;
    return _firstFailureOrSuccess(results);
  }
}

AppResult<void> _firstFailureOrSuccess(List<AppResult<void>> results) {
  for (final result in results) {
    if (result case AppError<void>()) return result;
  }
  return const AppSuccess<void>(null);
}

final class _FallbackSpeechOperation {
  final Completer<AppResult<void>> completion = Completer<AppResult<void>>();
  bool cancelled = false;
}
