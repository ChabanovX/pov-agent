import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pov_agent/features/assistant/data/adapters/generated_speech_audio_player.dart';
import 'package:pov_agent/features/assistant/data/datasources/just_audio_playback_backend.dart';
import 'package:pov_agent/features/assistant/data/mappers/pcm16_wav_encoder.dart';
import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Immutable counters for native local-speech playback acceptance tests.
@immutable
final class GeneratedSpeechPlaybackProbe {
  /// Creates a playback lifecycle snapshot.
  const GeneratedSpeechPlaybackProbe({
    required this.isPlaying,
    required this.startedCount,
    required this.completedCount,
    required this.stoppedCount,
    required this.failedCount,
  });

  /// Whether native output has started and has not reached a terminal state.
  final bool isPlaying;

  /// Number of utterances observed in a native playing state.
  final int startedCount;

  /// Number of utterances that reached natural audio completion.
  final int completedCount;

  /// Number of active operations interrupted by an explicit stop.
  final int stoppedCount;

  /// Number of non-stop operations that settled with a playback failure.
  final int failedCount;
}

/// Plays local synthesized PCM through a fresh `just_audio` player.
///
/// Each operation follows configure -> load -> activate -> play -> release.
/// The adapter owns one operation and one release barrier at a time. Explicit
/// stop invalidates the operation but always settles its [play] result as a
/// success; the stop command itself reports any native cleanup failure.
final class JustAudioGeneratedSpeechPlayer implements GeneratedSpeechAudioPlayer {
  /// Creates the production in-memory player.
  JustAudioGeneratedSpeechPlayer({
    JustAudioPlaybackBackend? backend,
    TargetPlatform? targetPlatform,
    Duration commandTimeout = const Duration(seconds: 10),
    Duration playbackGracePeriod = const Duration(seconds: 15),
  }) : assert(
         commandTimeout > Duration.zero,
         'Command timeout must be positive.',
       ),
       assert(
         !playbackGracePeriod.isNegative,
         'Playback grace period cannot be negative.',
       ),
       _backend = backend ?? PluginJustAudioPlaybackBackend(targetPlatform: targetPlatform),
       _commandTimeout = commandTimeout,
       _playbackGracePeriod = playbackGracePeriod;

  final JustAudioPlaybackBackend _backend;
  final Duration _commandTimeout;
  final Duration _playbackGracePeriod;

  _PlaybackOperation? _active;
  Future<_CapturedError?>? _releaseTask;
  Future<AppResult<void>>? _stopTask;
  Future<AppResult<void>>? _closeTask;
  var _releaseRequired = false;
  var _closing = false;
  var _closed = false;
  var _isPlaying = false;
  var _startedCount = 0;
  var _completedCount = 0;
  var _stoppedCount = 0;
  var _failedCount = 0;

  /// Current native playback counters used by device acceptance tests.
  @visibleForTesting
  GeneratedSpeechPlaybackProbe get playbackProbe => GeneratedSpeechPlaybackProbe(
    isPlaying: _isPlaying,
    startedCount: _startedCount,
    completedCount: _completedCount,
    stoppedCount: _stoppedCount,
    failedCount: _failedCount,
  );

  @override
  Future<AppResult<void>> play(GeneratedSpeechAudio audio) {
    if (_closing || _closed) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'local_speech_player_closed'),
        ),
      );
    }
    if (_active != null || _stopTask != null || _releaseRequired) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'local_speech_playback_busy'),
        ),
      );
    }

    late final Uint8List wavBytes;
    try {
      wavBytes = Pcm16WavEncoder.encode(audio);
    } on Object catch (error, stackTrace) {
      return Future.value(
        AppError(
          ValidationFailure(
            code: 'local_speech_audio_invalid',
            message: error.toString(),
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }

    final operation = _PlaybackOperation();
    _active = operation;
    late final Future<AppResult<void>> task;
    task = _playOnce(operation, audio, wavBytes).whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
    operation.task = task;
    return task;
  }

  Future<AppResult<void>> _playOnce(
    _PlaybackOperation operation,
    GeneratedSpeechAudio audio,
    Uint8List wavBytes,
  ) async {
    _CapturedError? playbackError;
    var naturallyCompleted = false;
    try {
      await _runCommand(_backend.configureSpeechMixing);
      if (!operation.stopRequested) {
        await _runCommand(
          () => _backend.load(wavBytes),
        );
      }
      if (!operation.stopRequested) await _runCommand(_backend.activate);
      if (!operation.stopRequested) {
        // Once the native play command is dispatched, output may become
        // audible before its asynchronous state callback reaches Dart. Treat
        // every later failure as post-start so fallback can never repeat a
        // partially heard utterance through another backend.
        operation.playDispatched = true;
        await _backend.play(onStarted: () => _recordStarted(operation)).timeout(audio.duration + _playbackGracePeriod);
        if (!operation.stopRequested) {
          naturallyCompleted = true;
          _recordCompleted(operation);
        }
      }
    } on Object catch (error, stackTrace) {
      playbackError = (error: error, stackTrace: stackTrace);
    }

    _releaseRequired = true;
    final releaseError = await _releaseBackend();
    if (operation.stopRequested) {
      _recordStopped(operation);
      return const AppSuccess<void>(null);
    }

    if (releaseError != null) {
      _recordFailed(operation);
      return AppError(
        DeviceUnavailableFailure(
          code: 'local_speech_playback_cleanup_failed',
          message: releaseError.error.toString(),
          cause: releaseError.error,
          stackTrace: releaseError.stackTrace,
        ),
      );
    }
    if (playbackError case final error?) {
      _recordFailed(operation);
      return _playbackFailure(operation, error);
    }
    if (!naturallyCompleted) {
      final unexpected = (
        error: StateError('Playback settled without a terminal outcome.'),
        stackTrace: StackTrace.current,
      );
      _recordFailed(operation);
      return _playbackFailure(operation, unexpected);
    }
    return const AppSuccess<void>(null);
  }

  AppError<void> _playbackFailure(
    _PlaybackOperation operation,
    _CapturedError captured,
  ) {
    final code = operation.playDispatched ? 'local_speech_playback_failed' : 'local_speech_playback_start_failed';
    return AppError(
      DeviceUnavailableFailure(
        code: code,
        message: captured.error.toString(),
        cause: captured.error,
        stackTrace: captured.stackTrace,
      ),
    );
  }

  Future<void> _runCommand(Future<void> Function() command) => command().timeout(_commandTimeout);

  Future<_CapturedError?> _releaseBackend() {
    final existing = _releaseTask;
    if (existing != null) return existing;

    late final Future<_CapturedError?> task;
    task = _captureRelease().whenComplete(() {
      if (identical(_releaseTask, task)) _releaseTask = null;
    });
    _releaseTask = task;
    return task;
  }

  Future<_CapturedError?> _captureRelease() async {
    try {
      await _backend.release().timeout(_commandTimeout);
      _releaseRequired = false;
      return null;
    } on Object catch (error, stackTrace) {
      _releaseRequired = true;
      return (error: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<AppResult<void>> stop() {
    final existing = _stopTask;
    if (existing != null) return existing;
    if (_closed) return Future.value(const AppSuccess<void>(null));

    final operation = _active;
    operation?.stopRequested = true;
    late final Future<AppResult<void>> task;
    task = _stopOnce(operation).whenComplete(() {
      if (identical(_stopTask, task)) _stopTask = null;
    });
    _stopTask = task;
    return task;
  }

  Future<AppResult<void>> _stopOnce(_PlaybackOperation? operation) async {
    _releaseRequired = _releaseRequired || operation != null;
    final firstRelease = await _releaseBackend();
    _CapturedError? operationSettlementError;
    if (operation != null) {
      try {
        await operation.task.timeout(_commandTimeout);
      } on Object catch (error, stackTrace) {
        // A command such as iOS activation may finish after an early release.
        // Stop cannot claim quiescence until the cancelled operation settles.
        operationSettlementError = (error: error, stackTrace: stackTrace);
      }
      _recordStopped(operation);
    }
    final finalRelease = await _releaseBackend();
    final error = operationSettlementError ?? finalRelease ?? (_releaseRequired ? firstRelease : null);
    if (error == null) return const AppSuccess<void>(null);
    return AppError(
      DeviceUnavailableFailure(
        code: 'local_speech_playback_stop_failed',
        message: error.error.toString(),
        cause: error.error,
        stackTrace: error.stackTrace,
      ),
    );
  }

  @override
  Future<AppResult<void>> close() {
    if (_closed) return Future.value(const AppSuccess<void>(null));
    final existing = _closeTask;
    if (existing != null) return existing;
    _closing = true;

    late final Future<AppResult<void>> task;
    task = _closeOnce().whenComplete(() {
      if (identical(_closeTask, task)) _closeTask = null;
    });
    _closeTask = task;
    return task;
  }

  Future<AppResult<void>> _closeOnce() async {
    final stopped = await stop();
    if (stopped case AppError<void>(:final failure)) {
      return AppError(
        DeviceUnavailableFailure(
          code: 'local_speech_player_close_failed',
          message: failure.message,
          cause: failure.cause,
          stackTrace: failure.stackTrace,
        ),
      );
    }
    try {
      await _backend.close().timeout(_commandTimeout);
      _closed = true;
      return const AppSuccess<void>(null);
    } on Object catch (error, stackTrace) {
      return AppError(
        DeviceUnavailableFailure(
          code: 'local_speech_player_close_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _recordStarted(_PlaybackOperation operation) {
    if (operation.started || operation.terminalRecorded) return;
    operation.started = true;
    _isPlaying = true;
    _startedCount += 1;
  }

  void _recordCompleted(_PlaybackOperation operation) {
    if (operation.terminalRecorded) return;
    operation.terminalRecorded = true;
    _isPlaying = false;
    _completedCount += 1;
  }

  void _recordStopped(_PlaybackOperation operation) {
    if (operation.terminalRecorded) return;
    operation.terminalRecorded = true;
    _isPlaying = false;
    _stoppedCount += 1;
  }

  void _recordFailed(_PlaybackOperation operation) {
    if (operation.terminalRecorded) return;
    operation.terminalRecorded = true;
    _isPlaying = false;
    _failedCount += 1;
  }
}

typedef _CapturedError = ({Object error, StackTrace stackTrace});

final class _PlaybackOperation {
  late final Future<AppResult<void>> task;
  bool stopRequested = false;
  bool playDispatched = false;
  bool started = false;
  bool terminalRecorded = false;
}
