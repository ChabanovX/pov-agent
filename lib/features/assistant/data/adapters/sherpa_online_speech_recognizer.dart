import 'dart:async';
import 'dart:typed_data';

import 'package:pov_agent/features/assistant/application/models/asr_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/ffi/sherpa_online_recognition_worker.dart';
import 'package:pov_agent/features/assistant/data/mappers/speech_recognition_failure_mapper.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Creates the lazily spawned persistent ASR worker.
typedef OnlineRecognitionWorkerFactory = Future<OnlineRecognitionWorker> Function();

/// Connects in-memory microphone capture to persistent sherpa-onnx decoding.
///
/// This adapter owns one microphone source and one lazily spawned worker. Model
/// loading may replace native model ownership only after the active handle has
/// stopped. A handle owns capture and subscriptions until its stop succeeds;
/// failed cleanup stays retryable instead of clearing the single-flight gate.
final class SherpaOnlineSpeechRecognizer implements SpeechRecognizer {
  /// Creates the production recognizer around injected runtime policy.
  factory SherpaOnlineSpeechRecognizer({
    required MicrophoneAudioSource audioSource,
    required AsrRuntimeConfiguration configuration,
    OnlineRecognitionWorkerFactory? workerFactory,
  }) {
    return SherpaOnlineSpeechRecognizer._(
      audioSource,
      configuration,
      workerFactory ?? SherpaOnlineRecognitionWorker.spawn,
    );
  }

  SherpaOnlineSpeechRecognizer._(
    this._audioSource,
    this._configuration,
    this._workerFactory,
  );

  final MicrophoneAudioSource _audioSource;
  final AsrRuntimeConfiguration _configuration;
  final OnlineRecognitionWorkerFactory _workerFactory;

  OnlineRecognitionWorker? _worker;
  Future<OnlineRecognitionWorker>? _workerSpawnTask;
  _SherpaSpeechRecognitionHandle? _activeHandle;
  Future<AppResult<SpeechRecognitionHandle>>? _startTask;
  Future<AppResult<void>>? _lifecycleTask;
  Future<AppResult<void>>? _closeTask;
  var _modelLoaded = false;
  var _workerMayOwnModel = false;
  var _closed = false;
  VerifiedAsrModelBundle? _loadedBundle;

  @override
  Future<AppResult<void>> loadModel(VerifiedAsrModelBundle bundle) {
    return _runExclusive(
      () async {
        await _settlePendingStart();
        final activeHandle = _activeHandle;
        if (activeHandle != null) {
          final stopResult = await activeHandle.stop();
          if (stopResult case AppError<void>()) return stopResult;
        }

        try {
          final worker = await _getOrSpawnWorker();
          _modelLoaded = false;
          _loadedBundle = null;
          // Replacement begins by freeing the previous recognizer. If that
          // cleanup fails, readiness is lost but native ownership remains
          // possible and a later unload must retry it.
          _workerMayOwnModel = true;
          await worker.load(bundle, _configuration);
          _modelLoaded = true;
          _loadedBundle = bundle;
          return const AppSuccess<void>(null);
        } on Object catch (error, stackTrace) {
          if (error is Error) rethrow;
          return AppError<void>(
            SpeechRecognitionFailureMapper.map(
              error,
              stackTrace,
              fallbackCode: 'asr_model_load_failed',
            ),
          );
        }
      },
    );
  }

  @override
  Future<AppResult<SpeechRecognitionHandle>> start() {
    if (_closed || _closeTask != null) {
      return Future.value(
        const AppError<SpeechRecognitionHandle>(
          UnexpectedFailure(code: 'asr_recognizer_closed'),
        ),
      );
    }
    if (_lifecycleTask != null) {
      return Future.value(
        const AppError<SpeechRecognitionHandle>(
          UnexpectedFailure(code: 'asr_recognizer_busy'),
        ),
      );
    }
    if (!_modelLoaded && _loadedBundle == null) {
      return Future.value(
        const AppError<SpeechRecognitionHandle>(
          UnexpectedFailure(code: 'asr_model_not_loaded'),
        ),
      );
    }
    if (_activeHandle != null) {
      return Future.value(
        const AppError<SpeechRecognitionHandle>(
          UnexpectedFailure(code: 'asr_stream_busy'),
        ),
      );
    }
    if (_startTask != null) {
      return Future.value(
        const AppError<SpeechRecognitionHandle>(
          UnexpectedFailure(code: 'asr_stream_busy'),
        ),
      );
    }

    late final Future<AppResult<SpeechRecognitionHandle>> task;
    task = _startOnce().whenComplete(() {
      if (identical(_startTask, task)) _startTask = null;
    });
    _startTask = task;
    return task;
  }

  Future<AppResult<SpeechRecognitionHandle>> _startOnce() async {
    try {
      var worker = _worker;
      if (worker?.isTerminallyUnavailable ?? false) {
        _modelLoaded = false;
        worker = await _getOrSpawnWorker();
      }
      if (!_modelLoaded) {
        final bundle = _loadedBundle;
        if (bundle == null) {
          return const AppError<SpeechRecognitionHandle>(
            UnexpectedFailure(code: 'asr_model_not_loaded'),
          );
        }
        worker ??= await _getOrSpawnWorker();
        _workerMayOwnModel = true;
        await worker.load(bundle, _configuration);
        _modelLoaded = true;
      }
      if (worker == null) {
        return const AppError<SpeechRecognitionHandle>(
          UnexpectedFailure(code: 'asr_worker_unavailable'),
        );
      }
      final handle = await _SherpaSpeechRecognitionHandle.start(
        audioSource: _audioSource,
        worker: worker,
        sampleRateHz: _configuration.sampleRateHz,
        onStopped: _clearActiveHandle,
      );
      _activeHandle = handle;
      return AppSuccess<SpeechRecognitionHandle>(handle);
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<SpeechRecognitionHandle>(
        SpeechRecognitionFailureMapper.map(
          error,
          stackTrace,
          fallbackCode: 'asr_stream_start_failed',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> unload() {
    return _runExclusive(
      () async {
        await _settlePendingStart();
        final handle = _activeHandle;
        if (handle != null) {
          final stopResult = await handle.stop();
          if (stopResult case AppError<void>()) return stopResult;
        }

        final worker = _worker;
        if (worker == null || !_workerMayOwnModel) {
          _modelLoaded = false;
          _loadedBundle = null;
          return const AppSuccess<void>(null);
        }
        try {
          if (worker.isTerminallyUnavailable) {
            await _disposeTerminalWorker(worker);
          } else {
            await worker.unload();
          }
          _modelLoaded = false;
          _workerMayOwnModel = false;
          _loadedBundle = null;
          return const AppSuccess<void>(null);
        } on Object catch (error, stackTrace) {
          if (error is Error) rethrow;
          return AppError<void>(
            SpeechRecognitionFailureMapper.map(
              error,
              stackTrace,
              fallbackCode: 'asr_model_unload_failed',
            ),
          );
        }
      },
    );
  }

  @override
  Future<AppResult<void>> close() {
    if (_closed) return Future.value(const AppSuccess<void>(null));
    final activeTask = _closeTask;
    if (activeTask != null) return activeTask;
    if (_lifecycleTask != null) {
      return Future.value(
        const AppError<void>(
          UnexpectedFailure(code: 'asr_recognizer_busy'),
        ),
      );
    }

    late final Future<AppResult<void>> task;
    task = _closeOnce().then((result) {
      if (result case AppError<void>()) _closeTask = null;
      return result;
    });
    _closeTask = task;
    return task;
  }

  Future<AppResult<void>> _closeOnce() async {
    AppFailure? failure;
    await _settlePendingStart();
    final handle = _activeHandle;
    if (handle != null) {
      final result = await handle.stop();
      if (result case AppError<void>(:final failure)) {
        return AppError<void>(failure);
      }
    }

    try {
      await _audioSource.close();
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      failure = SpeechRecognitionFailureMapper.map(
        error,
        stackTrace,
        fallbackCode: 'microphone_close_failed',
      );
    }

    final worker = _worker;
    if (worker != null) {
      try {
        await worker.close();
      } on Object catch (error, stackTrace) {
        if (error is Error) rethrow;
        failure ??= SpeechRecognitionFailureMapper.map(
          error,
          stackTrace,
          fallbackCode: 'asr_worker_close_failed',
        );
      }
    }

    if (failure != null) return AppError<void>(failure);
    _modelLoaded = false;
    _workerMayOwnModel = false;
    _loadedBundle = null;
    _closed = true;
    return const AppSuccess<void>(null);
  }

  Future<OnlineRecognitionWorker> _getOrSpawnWorker() async {
    final worker = _worker;
    if (worker != null && !worker.isTerminallyUnavailable) return worker;
    if (worker != null) await _disposeTerminalWorker(worker);
    final activeTask = _workerSpawnTask;
    if (activeTask != null) return activeTask;

    late final Future<OnlineRecognitionWorker> task;
    task = _workerFactory().then(
      (spawned) {
        _worker = spawned;
        _workerSpawnTask = null;
        return spawned;
      },
      onError: (Object error, StackTrace stackTrace) {
        _workerSpawnTask = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _workerSpawnTask = task;
    return task;
  }

  Future<void> _disposeTerminalWorker(OnlineRecognitionWorker worker) async {
    await worker.close();
    if (identical(_worker, worker)) _worker = null;
    _modelLoaded = false;
    _workerMayOwnModel = false;
  }

  Future<void> _settlePendingStart() async {
    final pendingStart = _startTask;
    if (pendingStart != null) await pendingStart;
  }

  Future<AppResult<void>> _runExclusive(
    Future<AppResult<void>> Function() operation,
  ) {
    if (_closed || _closeTask != null) {
      return Future.value(
        const AppError<void>(
          UnexpectedFailure(code: 'asr_recognizer_closed'),
        ),
      );
    }
    if (_lifecycleTask != null) {
      return Future.value(
        const AppError<void>(
          UnexpectedFailure(code: 'asr_recognizer_busy'),
        ),
      );
    }

    late final Future<AppResult<void>> task;
    task = operation().whenComplete(() {
      if (identical(_lifecycleTask, task)) _lifecycleTask = null;
    });
    _lifecycleTask = task;
    return task;
  }

  void _clearActiveHandle(_SherpaSpeechRecognitionHandle handle) {
    if (!identical(_activeHandle, handle)) return;
    _activeHandle = null;
    if (_worker?.isTerminallyUnavailable ?? false) _modelLoaded = false;
  }
}

final class _SherpaSpeechRecognitionHandle implements SpeechRecognitionHandle {
  _SherpaSpeechRecognitionHandle._(
    this._audioSource,
    this._worker,
    this._onStopped,
  );

  static Future<_SherpaSpeechRecognitionHandle> start({
    required MicrophoneAudioSource audioSource,
    required OnlineRecognitionWorker worker,
    required int sampleRateHz,
    required void Function(_SherpaSpeechRecognitionHandle handle) onStopped,
  }) async {
    final handle = _SherpaSpeechRecognitionHandle._(
      audioSource,
      worker,
      onStopped,
    );
    handle._workerSubscription = worker.events.listen(handle._onWorkerEvent);
    try {
      await worker.start();
      final audio = await audioSource.start(sampleRateHz: sampleRateHz);
      handle._audioSubscription = audio.listen(
        handle._onAudio,
        onError: handle._onAudioError,
        onDone: handle._onAudioDone,
      );
      return handle;
    } on Object catch (startError, startStackTrace) {
      await handle._workerSubscription?.cancel();
      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      try {
        await audioSource.stop();
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }
      try {
        await worker.stop();
      } on Object catch (error, stackTrace) {
        cleanupError ??= error;
        cleanupStackTrace ??= stackTrace;
      }
      // A stale start can be stopped before presentation ever listens. A
      // single-subscription controller defers its close future until then.
      unawaited(handle._events.close());
      final terminalCleanupError = cleanupError;
      if (terminalCleanupError != null) {
        Error.throwWithStackTrace(
          terminalCleanupError,
          cleanupStackTrace ?? StackTrace.current,
        );
      }
      Error.throwWithStackTrace(startError, startStackTrace);
    }
  }

  final MicrophoneAudioSource _audioSource;
  final OnlineRecognitionWorker _worker;
  final void Function(_SherpaSpeechRecognitionHandle handle) _onStopped;
  final StreamController<SpeechRecognitionEvent> _events = StreamController<SpeechRecognitionEvent>();

  StreamSubscription<AsrWorkerEvent>? _workerSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Future<AppResult<void>>? _stopTask;
  var _stopping = false;
  var _stopped = false;
  var _failurePublished = false;
  var _lastSegmentId = 0;
  var _lastRevision = 0;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<AppResult<void>> resetForNextSegment() async {
    if (_stopped || _stopping) {
      return const AppError<void>(
        UnexpectedFailure(code: 'asr_stream_not_active'),
      );
    }
    try {
      await _worker.reset();
      return const AppSuccess<void>(null);
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(
        SpeechRecognitionFailureMapper.map(
          error,
          stackTrace,
          fallbackCode: 'asr_stream_reset_failed',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> stop() {
    if (_stopped) return Future.value(const AppSuccess<void>(null));
    final activeTask = _stopTask;
    if (activeTask != null) return activeTask;

    late final Future<AppResult<void>> task;
    task = _stopOnce().then((result) {
      if (result case AppError<void>()) {
        _stopping = false;
        _stopTask = null;
      }
      return result;
    });
    _stopTask = task;
    return task;
  }

  Future<AppResult<void>> _stopOnce() async {
    _stopping = true;
    AppFailure? failure;

    try {
      await _audioSource.stop();
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      failure = SpeechRecognitionFailureMapper.map(
        error,
        stackTrace,
        fallbackCode: 'microphone_stop_failed',
      );
    }
    await _audioSubscription?.cancel();

    if (!_worker.isTerminallyUnavailable) {
      try {
        await _worker.stop();
      } on Object catch (error, stackTrace) {
        if (error is Error) rethrow;
        // An isolate may die while this stop request is in flight. Once dead,
        // it cannot retain native stream ownership, so only local teardown and
        // foreground port disposal remain necessary.
        if (!_worker.isTerminallyUnavailable) {
          failure ??= SpeechRecognitionFailureMapper.map(
            error,
            stackTrace,
            fallbackCode: 'asr_stream_stop_failed',
          );
        }
      }
    }

    if (failure != null) return AppError<void>(failure);
    await _workerSubscription?.cancel();
    // Do not make native cleanup depend on an optional presentation listener.
    unawaited(_events.close());
    _stopped = true;
    _stopping = false;
    _onStopped(this);
    return const AppSuccess<void>(null);
  }

  void _onAudio(Uint8List chunk) {
    if (_stopping || _stopped) return;
    unawaited(_worker.acceptAudio(chunk));
  }

  void _onAudioError(Object error, StackTrace stackTrace) {
    if (_stopping || _stopped) return;
    if (error is Error) Error.throwWithStackTrace(error, stackTrace);
    _publishFailure(
      SpeechRecognitionFailureMapper.map(
        error,
        stackTrace,
        fallbackCode: 'microphone_stream_failed',
      ),
    );
  }

  void _onAudioDone() {
    if (_stopping || _stopped) return;
    _publishFailure(
      const DeviceUnavailableFailure(
        code: 'microphone_stream_ended_unexpectedly',
      ),
    );
  }

  void _onWorkerEvent(AsrWorkerEvent event) {
    _lastSegmentId = event.segmentId;
    _lastRevision = event.revision;
    switch (event) {
      case AsrWorkerHypothesis(:final transcript):
        _events.add(
          SpeechRecognitionHypothesis(
            segmentId: event.segmentId,
            revision: event.revision,
            transcript: transcript,
          ),
        );
      case AsrWorkerEndpoint(:final transcript, :final reason):
        _events.add(
          SpeechRecognitionEndpoint(
            segmentId: event.segmentId,
            revision: event.revision,
            transcript: transcript,
            reason: reason,
          ),
        );
      case AsrWorkerFailure(:final failure):
        _publishFailure(
          SpeechRecognitionFailureMapper.map(
            failure,
            StackTrace.current,
            fallbackCode: 'asr_stream_failed',
          ),
          segmentId: event.segmentId,
          revision: event.revision,
        );
    }
  }

  void _publishFailure(
    AppFailure failure, {
    int? segmentId,
    int? revision,
  }) {
    if (_failurePublished || _stopped || _events.isClosed) return;
    _failurePublished = true;
    final failureRevision = revision ?? _lastRevision + 1;
    _events.add(
      SpeechRecognitionFailure(
        segmentId: segmentId ?? _lastSegmentId,
        revision: failureRevision,
        failure: failure,
      ),
    );
    unawaited(stop());
  }
}
