import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Adapts the process-wide system TTS engine to [SpeechSynthesizer].
///
/// `flutter_tts` exposes one static method-channel callback owner and does not
/// tag callbacks with an utterance ID. This adapter therefore owns exactly one
/// plugin instance and one operation slot. Native completion callbacks settle
/// the slot; a watchdog and an explicit stop barrier prevent interruptions or
/// late cancellation callbacks from leaving speech active indefinitely.
final class FlutterTtsSpeechSynthesizer implements SpeechSynthesizer {
  /// Creates the process-owned system speech adapter.
  factory FlutterTtsSpeechSynthesizer({
    required String preferredLanguage,
    FlutterTts? flutterTts,
    TargetPlatform? targetPlatform,
    Duration commandTimeout = const Duration(seconds: 10),
    Duration utteranceTimeout = const Duration(seconds: 30),
    Duration cancellationDrainTimeout = const Duration(seconds: 1),
    Duration iosSessionReleaseRetryDelay = const Duration(milliseconds: 50),
    int iosSessionReleaseAttempts = 4,
  }) {
    assert(
      !iosSessionReleaseRetryDelay.isNegative,
      'The iOS session-release retry delay cannot be negative.',
    );
    assert(
      iosSessionReleaseAttempts > 0,
      'The iOS session-release attempt count must be positive.',
    );
    return FlutterTtsSpeechSynthesizer._(
      preferredLanguage: preferredLanguage.trim(),
      tts: flutterTts ?? FlutterTts(),
      targetPlatform: targetPlatform ?? defaultTargetPlatform,
      commandTimeout: commandTimeout,
      utteranceTimeout: utteranceTimeout,
      cancellationDrainTimeout: cancellationDrainTimeout,
      iosSessionReleaseRetryDelay: iosSessionReleaseRetryDelay,
      iosSessionReleaseAttempts: iosSessionReleaseAttempts,
    ).._registerNativeHandlers();
  }

  FlutterTtsSpeechSynthesizer._({
    required this._preferredLanguage,
    required this._tts,
    required this._targetPlatform,
    required this._commandTimeout,
    required this._utteranceTimeout,
    required this._cancellationDrainTimeout,
    required this._iosSessionReleaseRetryDelay,
    required this._iosSessionReleaseAttempts,
  });

  static final AppLogger _logger = AppLogger(
    'FlutterTtsSpeechSynthesizer',
  );

  final String _preferredLanguage;
  final FlutterTts _tts;
  final TargetPlatform _targetPlatform;
  final Duration _commandTimeout;
  final Duration _utteranceTimeout;
  final Duration _cancellationDrainTimeout;
  final Duration _iosSessionReleaseRetryDelay;
  final int _iosSessionReleaseAttempts;

  _SpeechOperation? _active;
  Future<AppResult<void>>? _configurationTask;
  Future<void>? _speechStartTask;
  Future<AppResult<void>>? _stopTask;
  Future<AppResult<void>>? _closeTask;
  Future<AppResult<void>>? _iosSessionReleaseTask;
  Completer<void>? _expectedCancellation;
  String? _resolvedLanguage;
  var _engineMayBeSpeaking = false;
  var _iosSessionActive = false;
  var _closed = false;

  /// The installed English locale selected during lazy initialization.
  @visibleForTesting
  String? get resolvedLanguage => _resolvedLanguage;

  @override
  Future<AppResult<void>> speak(String text) {
    final utterance = text.trim();
    if (_closed) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'system_speech_closed'),
        ),
      );
    }
    if (utterance.isEmpty) {
      return Future.value(
        const AppError(
          ValidationFailure(code: 'system_speech_empty_text'),
        ),
      );
    }
    if (_active != null || _speechStartTask != null || _engineMayBeSpeaking || _stopTask != null) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'system_speech_busy'),
        ),
      );
    }

    final operation = _SpeechOperation();
    operation.timeout = Timer(_utteranceTimeout, () {
      if (!identical(_active, operation)) return;
      _failOperationAndStop(
        operation,
        const AppError(
          DeviceUnavailableFailure(code: 'system_speech_timeout'),
        ),
      );
    });
    _active = operation;
    late final Future<void> startTask;
    startTask = _start(operation, utterance).whenComplete(() {
      if (identical(_speechStartTask, startTask)) _speechStartTask = null;
    });
    _speechStartTask = startTask;
    unawaited(startTask);
    return operation.completion.future;
  }

  Future<void> _start(_SpeechOperation operation, String text) async {
    final configuration = await _ensureConfigured();
    if (!identical(_active, operation) || _closed) return;
    if (configuration case AppError<void>()) {
      _completeOperation(operation, configuration);
      return;
    }

    if (_targetPlatform == TargetPlatform.iOS) {
      // The platform command may activate the session even if its reply times
      // out. Claim tentative ownership before dispatch so every failure and
      // concurrent close still sends a balancing deactivation command.
      _iosSessionActive = true;
      final activation = await _runNativeCommand(
        () => _tts.setSharedInstance(true),
        failureCode: 'system_speech_audio_session_unavailable',
      );
      if (!identical(_active, operation) || _closed) {
        await _deactivateIosSession();
        return;
      }
      if (activation case AppError<void>()) {
        _failOperationAndStop(operation, activation);
        return;
      }
    }

    _engineMayBeSpeaking = true;
    // flutter_tts 4.2.5 does not release Android audio focus from every
    // native error path. Its default no-focus mode avoids retaining focus.
    final accepted = await _runNativeCommand(
      () => _tts.speak(text),
      failureCode: 'system_speech_start_failed',
    );
    if (!identical(_active, operation)) return;
    if (accepted case AppError<void>()) {
      _failOperationAndStop(operation, accepted);
    }
  }

  Future<AppResult<void>> _ensureConfigured() {
    final existing = _configurationTask;
    if (existing != null) return existing;

    late final Future<AppResult<void>> task;
    task = _configure().then((result) {
      if (result is AppError<void> && identical(_configurationTask, task)) {
        _configurationTask = null;
      }
      return result;
    });
    _configurationTask = task;
    return task;
  }

  Future<AppResult<void>> _configure() async {
    if (_preferredLanguage.isEmpty || !_preferredLanguage.toLowerCase().startsWith('en-')) {
      return const AppError(
        ValidationFailure(code: 'system_speech_language_not_english'),
      );
    }

    final callbackMode = await _runNativeCommand(
      () => _tts.awaitSpeakCompletion(false),
      failureCode: 'system_speech_configuration_failed',
    );
    if (callbackMode case AppError<void>()) return callbackMode;

    if (_targetPlatform == TargetPlatform.android) {
      final queueMode = await _runNativeCommand(
        () => _tts.setQueueMode(0),
        failureCode: 'system_speech_queue_configuration_failed',
      );
      if (queueMode case AppError<void>()) return queueMode;
    }

    if (_targetPlatform == TargetPlatform.iOS) {
      final category = await _runNativeCommand(
        () => _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [
            // Explicit plugin deactivation omits notifyOthersOnDeactivation.
            // Mixing therefore preserves other apps' audio across every stop.
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        ),
        failureCode: 'system_speech_audio_configuration_failed',
      );
      if (category case AppError<void>()) return category;
      final autoStop = await _runNativeCommand(
        // The adapter balances activation after every terminal callback so the
        // plugin must not independently release the shared session.
        () => _tts.autoStopSharedSession(false),
        failureCode: 'system_speech_audio_configuration_failed',
      );
      if (autoStop case AppError<void>()) return autoStop;
    }

    for (final language in _languageCandidates()) {
      final selected = await _tryLanguage(language);
      if (selected) {
        _resolvedLanguage = language;
        if (language.toLowerCase() != _preferredLanguage.toLowerCase()) {
          _logger.w(
            'Preferred locale $_preferredLanguage is unavailable; using '
            '$language.',
          );
        }
        return const AppSuccess<void>(null);
      }
    }
    return const AppError(
      DeviceUnavailableFailure(
        code: 'system_speech_language_unavailable',
        message: 'No supported English voice is installed.',
      ),
    );
  }

  Iterable<String> _languageCandidates() sync* {
    final emitted = <String>{};
    for (final language in [
      _preferredLanguage,
      'en-US',
      'en-GB',
    ]) {
      if (emitted.add(language.toLowerCase())) yield language;
    }
  }

  Future<bool> _tryLanguage(String language) async {
    try {
      if (_targetPlatform == TargetPlatform.android) {
        final installed = await _tts
            .isLanguageInstalled(language)
            .timeout(
              _commandTimeout,
            );
        if (!_isAccepted(installed)) return false;
      }
      final result = await _tts.setLanguage(language).timeout(_commandTimeout);
      return _isAccepted(result);
    } on Object catch (error, stackTrace) {
      _logger.w(
        'Could not select system speech locale $language.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
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
    final speechStartTask = _speechStartTask;
    if (operation != null) {
      _completeOperation(
        operation,
        const AppSuccess<void>(null),
        engineSettled: false,
      );
    }

    AppFailure? stopFailure;
    AppFailure? deactivationFailure;
    final expectedCancellation = _engineMayBeSpeaking ? Completer<void>() : null;
    _expectedCancellation = expectedCancellation;

    if (_engineMayBeSpeaking) {
      final result = await _runNativeCommand(
        _tts.stop,
        failureCode: 'system_speech_stop_failed',
      );
      switch (result) {
        case AppSuccess<void>():
          _engineMayBeSpeaking = false;
        case AppError<void>(:final failure):
          stopFailure = failure;
      }
    }

    if (expectedCancellation != null && !expectedCancellation.isCompleted) {
      await Future.any<void>([
        expectedCancellation.future,
        Future<void>.delayed(_cancellationDrainTimeout),
      ]);
    }
    if (identical(_expectedCancellation, expectedCancellation)) {
      _expectedCancellation = null;
    }
    if (expectedCancellation?.isCompleted ?? false) {
      // A native cancellation is stronger evidence than a lost/rejected method
      // reply: the engine has actually discarded the active utterance.
      _engineMayBeSpeaking = false;
      stopFailure = null;
    }

    if (speechStartTask != null) await speechStartTask;
    final deactivation = await _deactivateIosSession();
    if (deactivation case AppError<void>(:final failure)) {
      deactivationFailure = failure;
    }
    final failure = stopFailure ?? deactivationFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  Future<AppResult<void>> _deactivateIosSession() {
    if (_targetPlatform != TargetPlatform.iOS) {
      return Future.value(const AppSuccess<void>(null));
    }

    final existing = _iosSessionReleaseTask;
    if (existing != null) return existing;
    if (!_iosSessionActive) {
      return Future.value(const AppSuccess<void>(null));
    }

    late final Future<AppResult<void>> task;
    task = _deactivateIosSessionWithRetry().whenComplete(() {
      if (identical(_iosSessionReleaseTask, task)) {
        _iosSessionReleaseTask = null;
      }
    });
    _iosSessionReleaseTask = task;
    return task;
  }

  Future<AppResult<void>> _deactivateIosSessionWithRetry() async {
    AppResult<void> result = const AppError(
      DeviceUnavailableFailure(
        code: 'system_speech_audio_session_release_failed',
      ),
    );
    for (var attempt = 0; attempt < _iosSessionReleaseAttempts; attempt += 1) {
      result = await _runNativeCommand(
        () => _tts.setSharedInstance(false),
        failureCode: 'system_speech_audio_session_release_failed',
      );
      if (result is AppSuccess<void>) {
        _iosSessionActive = false;
        return result;
      }
      if (result case AppError<void>(:final failure) when failure.cause != null) {
        return result;
      }
      if (attempt + 1 < _iosSessionReleaseAttempts) {
        // A physical iPhone can report AVAudioSession as busy briefly after
        // AVSpeechSynthesizer's terminal callback. The simulator does not
        // expose that hand-off window, so retry after native output unwinds.
        await Future<void>.delayed(_iosSessionReleaseRetryDelay);
      }
    }
    return result;
  }

  Future<AppResult<void>> _runNativeCommand(
    Future<dynamic> Function() command, {
    required String failureCode,
  }) async {
    try {
      final result = await command().timeout(_commandTimeout);
      if (_isAccepted(result)) return const AppSuccess<void>(null);
      return AppError(
        DeviceUnavailableFailure(
          code: failureCode,
          message: 'The system speech service rejected the command.',
        ),
      );
    } on Object catch (error, stackTrace) {
      return AppError(
        DeviceUnavailableFailure(
          code: failureCode,
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  bool _isAccepted(Object? result) => result == 1 || result == true;

  void _registerNativeHandlers() {
    _tts
      ..setStartHandler(_onNativeStart)
      ..setCompletionHandler(_onNativeCompletion)
      ..setCancelHandler(_onNativeCancellation)
      ..setPauseHandler(_onNativePause)
      ..setErrorHandler(_onNativeError);
  }

  void _onNativeStart() {
    final operation = _active;
    if (operation == null || _closed) return;
    operation.nativeStarted = true;
  }

  void _onNativeCompletion() {
    if (_completeExpectedStopCallback()) return;
    final operation = _active;
    if (operation == null || _closed || !operation.nativeStarted) return;
    unawaited(
      _settleNativeTerminal(
        operation,
        const AppSuccess<void>(null),
      ),
    );
  }

  void _onNativeCancellation() {
    if (_completeExpectedStopCallback()) return;
    final operation = _active;
    if (operation == null || _closed || !operation.nativeStarted) return;
    unawaited(
      _settleNativeTerminal(
        operation,
        const AppError(
          DeviceUnavailableFailure(code: 'system_speech_interrupted'),
        ),
      ),
    );
  }

  void _onNativePause() {
    if (_completeExpectedStopCallback()) return;
    final operation = _active;
    if (operation == null || _closed || !operation.nativeStarted) return;
    _failOperationAndStop(
      operation,
      const AppError(
        DeviceUnavailableFailure(code: 'system_speech_paused'),
      ),
    );
  }

  void _onNativeError(Object? message) {
    if (_completeExpectedStopCallback()) return;
    final operation = _active;
    if (operation == null || _closed) return;
    _failOperationAndStop(
      operation,
      AppError(
        DeviceUnavailableFailure(
          code: 'system_speech_native_error',
          message: message?.toString(),
          cause: message,
        ),
      ),
    );
  }

  void _failOperationAndStop(
    _SpeechOperation operation,
    AppError<void> failure,
  ) {
    if (!identical(_active, operation)) return;
    _active = null;
    operation.timeout?.cancel();
    unawaited(_stopBeforeSettlingFailure(operation, failure));
  }

  Future<void> _stopBeforeSettlingFailure(
    _SpeechOperation operation,
    AppError<void> failure,
  ) async {
    final stopResult = await stop();
    final terminalResult = switch (stopResult) {
      AppSuccess<void>() => failure,
      AppError<void>() => stopResult,
    };
    if (!operation.completion.isCompleted) {
      operation.completion.complete(terminalResult);
    }
  }

  bool _completeExpectedStopCallback() {
    final expected = _expectedCancellation;
    if (expected == null) return false;
    if (!expected.isCompleted) expected.complete();
    return true;
  }

  Future<void> _settleNativeTerminal(
    _SpeechOperation operation,
    AppResult<void> result,
  ) async {
    if (!identical(_active, operation)) return;
    operation.timeout?.cancel();
    operation.timeout = null;
    _engineMayBeSpeaking = false;
    final deactivation = await _deactivateIosSession();
    if (!identical(_active, operation)) return;
    if (deactivation case AppError<void>()) {
      _completeOperation(operation, deactivation);
      return;
    }
    _completeOperation(operation, result);
  }

  void _completeOperation(
    _SpeechOperation operation,
    AppResult<void> result, {
    bool engineSettled = true,
  }) {
    if (!identical(_active, operation)) return;
    _active = null;
    operation.timeout?.cancel();
    if (engineSettled) _engineMayBeSpeaking = false;
    if (!operation.completion.isCompleted) operation.completion.complete(result);
  }

  @override
  Future<AppResult<void>> close() {
    final existing = _closeTask;
    if (existing != null) return existing;

    _closed = true;
    late final Future<AppResult<void>> task;
    task = _closeOnce().then((result) {
      if (result is AppError<void> && identical(_closeTask, task)) {
        _closeTask = null;
      }
      return result;
    });
    _closeTask = task;
    return task;
  }

  Future<AppResult<void>> _closeOnce() async {
    final result = await stop();
    if (result is AppError<void>) return result;
    _tts
      ..setStartHandler(_ignoreVoidCallback)
      ..setCompletionHandler(_ignoreVoidCallback)
      ..setCancelHandler(_ignoreVoidCallback)
      ..setPauseHandler(_ignoreVoidCallback)
      ..setErrorHandler(_ignoreErrorCallback);
    return const AppSuccess<void>(null);
  }
}

final class _SpeechOperation {
  _SpeechOperation();

  final Completer<AppResult<void>> completion = Completer<AppResult<void>>();
  Timer? timeout;
  bool nativeStarted = false;
}

void _ignoreVoidCallback() {}

void _ignoreErrorCallback(Object? _) {}
