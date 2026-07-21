import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/services/wake_phrase_detector.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A semantic update produced by [ObserverVoiceInputSession].
sealed class ObserverVoiceInputUpdate {
  /// Defines a model, phase, transcript, question, or failure update.
  const ObserverVoiceInputUpdate();
}

/// The latest verified-ASR store state.
final class ObserverVoiceModelStateChanged extends ObserverVoiceInputUpdate {
  /// Creates a model-state projection update.
  const ObserverVoiceModelStateChanged(this.state);

  /// Current verified bundle acquisition state.
  final ModelStoreState<VerifiedAsrModelBundle> state;
}

/// Recognition is armed for the configured wake phrase.
final class ObserverVoiceWatching extends ObserverVoiceInputUpdate {
  /// Creates an armed update.
  const ObserverVoiceWatching();
}

/// One whole-token wake phrase opened a new voice turn.
final class ObserverVoiceWakeDetected extends ObserverVoiceInputUpdate {
  /// Creates a wake update for [turnId].
  const ObserverVoiceWakeDetected({
    required this.turnId,
    required this.trailingTranscript,
  });

  /// Monotonic voice-turn identifier.
  final int turnId;

  /// Question words already decoded after the wake phrase.
  final String trailingTranscript;
}

/// The voice turn entered listening after its recognition stream reset.
final class ObserverVoiceListeningStarted extends ObserverVoiceInputUpdate {
  /// Creates a listening update for [turnId].
  const ObserverVoiceListeningStarted({
    required this.turnId,
    required this.transcript,
  });

  /// Monotonic voice-turn identifier.
  final int turnId;

  /// Current normalized question, possibly empty.
  final String transcript;
}

/// A cumulative replacement for the active voice question.
final class ObserverVoiceTranscriptChanged extends ObserverVoiceInputUpdate {
  /// Creates a transcript update for [turnId].
  const ObserverVoiceTranscriptChanged({
    required this.turnId,
    required this.transcript,
  });

  /// Monotonic voice-turn identifier.
  final int turnId;

  /// Current normalized question transcript.
  final String transcript;
}

/// Exactly one completed question from a voice turn.
final class ObserverVoiceQuestionCompleted extends ObserverVoiceInputUpdate {
  /// Creates a terminal question update for [turnId].
  const ObserverVoiceQuestionCompleted({
    required this.turnId,
    required this.question,
  });

  /// Monotonic voice-turn identifier.
  final int turnId;

  /// Non-empty normalized question submitted to Qwen.
  final String question;
}

/// A recoverable ASR-model load failure after bundle verification.
final class ObserverVoiceModelLoadFailed extends ObserverVoiceInputUpdate {
  /// Creates a native-load failure update.
  const ObserverVoiceModelLoadFailed(this.failure);

  /// Normalized native recognizer failure.
  final AppFailure failure;
}

/// A recoverable permission, capture, decode, silence, or input failure.
final class ObserverVoiceInputFailed extends ObserverVoiceInputUpdate {
  /// Creates a hands-free failure update for an optional active [turnId].
  const ObserverVoiceInputFailed({
    required this.failure,
    this.turnId,
  });

  /// Voice turn that failed, or `null` while arming the watcher.
  final int? turnId;

  /// Normalized actionable failure.
  final AppFailure failure;
}

/// Creates the wall-clock deadline for one question turn.
typedef ObserverVoiceDeadlineFactory =
    Timer Function(
      Duration duration,
      void Function() onDeadline,
    );

/// Owns verified ASR preparation and one live recognition handle.
///
/// The session translates cumulative native hypotheses into wake, listening,
/// and exactly-once question updates. It never owns Qwen, dialogue history, or
/// speech arbitration; those remain in `ObserverBloc`'s sequential queue.
/// Every pause invalidates callbacks before awaiting capture teardown, so late
/// native endpoints cannot submit a second question or cross a TTS boundary.
final class ObserverVoiceInputSession {
  /// Creates an idle foreground voice-input owner.
  factory ObserverVoiceInputSession({
    required AsrModelStore modelStore,
    required MicrophonePermissionGateway permissionGateway,
    required SpeechRecognizer speechRecognizer,
    required WakePhraseDetector wakePhraseDetector,
    required Duration questionDeadline,
    required void Function(ObserverVoiceInputUpdate update) onUpdate,
    ObserverVoiceDeadlineFactory? deadlineFactory,
  }) {
    return ObserverVoiceInputSession._(
      modelStore,
      permissionGateway,
      speechRecognizer,
      wakePhraseDetector,
      questionDeadline,
      onUpdate,
      deadlineFactory ?? Timer.new,
    );
  }

  ObserverVoiceInputSession._(
    this._modelStore,
    this._permissionGateway,
    this._speechRecognizer,
    this._wakePhraseDetector,
    this._questionDeadline,
    this._onUpdate,
    this._deadlineFactory,
  );

  final AsrModelStore _modelStore;
  final MicrophonePermissionGateway _permissionGateway;
  final SpeechRecognizer _speechRecognizer;
  final WakePhraseDetector _wakePhraseDetector;
  final Duration _questionDeadline;
  final void Function(ObserverVoiceInputUpdate update) _onUpdate;
  final ObserverVoiceDeadlineFactory _deadlineFactory;

  StreamSubscription<ModelStoreState<VerifiedAsrModelBundle>>? _modelSubscription;
  SpeechRecognitionHandle? _recognitionHandle;
  // The handle subscription crosses methods by design and is cancelled by
  // pause before capture teardown, then defensively again during close.
  // ignore: cancel_subscriptions
  StreamSubscription<SpeechRecognitionEvent>? _recognitionSubscription;
  Future<void>? _recognitionEventTask;
  Future<AppResult<void>>? _watchTask;
  Future<AppResult<void>>? _pauseTask;
  Future<AppResult<void>>? _suspendTask;
  Future<AppResult<void>>? _closeTask;
  Timer? _questionTimer;
  VerifiedAsrModelBundle? _loadedBundle;
  _VoiceInputMode _mode = _VoiceInputMode.idle;
  String _questionPrefix = '';
  String _questionHypothesis = '';
  var _epoch = 0;
  var _turnSequence = 0;
  int? _activeTurnId;
  var _expectedSegmentId = 0;
  var _recognizerLoaded = false;
  var _closed = false;

  /// Latest synchronously observable ASR model-store state.
  ModelStoreState<VerifiedAsrModelBundle> get modelState => _modelStore.current;

  /// Whether microphone capture and native decoding currently own a handle.
  bool get isWatching => _recognitionHandle != null;

  /// Resolves the verified ASR bundle without requesting microphone access.
  ///
  /// Startup uses this to acquire Qwen and ASR concurrently while recognition
  /// remains disarmed until the text-generation model is also ready.
  Future<AppResult<VerifiedAsrModelBundle>> prepareModel() {
    if (_closed) {
      return Future.value(
        const AppError(
          UnexpectedFailure(code: 'observer_voice_session_closed'),
        ),
      );
    }
    _ensureModelSubscription();
    return _resolveBundle();
  }

  /// Prepares the model, obtains permission, and arms recognition once.
  ///
  /// Concurrent calls share one operation. A recoverable failure is both
  /// returned and emitted so the Bloc can expose a retry action.
  Future<AppResult<void>> watch() {
    final active = _watchTask;
    if (active != null) return active;
    if (_closed) {
      return Future.value(
        const AppError(
          UnexpectedFailure(code: 'observer_voice_session_closed'),
        ),
      );
    }
    if (_recognitionHandle != null && _mode != _VoiceInputMode.idle) {
      return Future.value(const AppSuccess<void>(null));
    }

    final epoch = ++_epoch;
    _ensureModelSubscription();
    late final Future<AppResult<void>> task;
    task = _watchForEpoch(epoch).whenComplete(() {
      if (identical(_watchTask, task)) _watchTask = null;
    });
    _watchTask = task;
    return task;
  }

  /// Stops capture and invalidates all recognition callbacks before awaiting.
  Future<AppResult<void>> pause() {
    final active = _pauseTask;
    if (active != null) return active;
    _epoch += 1;
    _cancelQuestionTimer();
    _mode = _VoiceInputMode.idle;
    _activeTurnId = null;
    _questionPrefix = '';
    _questionHypothesis = '';

    late final Future<AppResult<void>> task;
    task = _pauseOnce().whenComplete(() {
      if (identical(_pauseTask, task)) _pauseTask = null;
    });
    _pauseTask = task;
    return task;
  }

  /// Pauses recognition, suspends bundle work, and unloads native ASR memory.
  Future<AppResult<void>> suspend() {
    final active = _suspendTask;
    if (active != null) return active;
    late final Future<AppResult<void>> task;
    task = _suspendOnce().whenComplete(() {
      if (identical(_suspendTask, task)) _suspendTask = null;
    });
    _suspendTask = task;
    return task;
  }

  /// Permanently stops owned subscriptions without closing injected ports.
  Future<AppResult<void>> close() {
    final active = _closeTask;
    if (active != null) return active;
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

  // ── Preparation and arming ──────────────────────────────────────

  Future<AppResult<void>> _watchForEpoch(int epoch) async {
    // A failed pause retains its handle so retry can finish native teardown
    // before requesting another single-flight recognition stream.
    if (_recognitionHandle != null) {
      final cleanupResult = await _detachAndStopRecognition();
      if (!_isCurrent(epoch)) return const AppSuccess<void>(null);
      if (cleanupResult case AppError<void>(:final failure)) {
        _onUpdate(ObserverVoiceInputFailed(failure: failure));
        return AppError<void>(failure);
      }
    }

    final bundleResult = await _resolveBundle();
    if (!_isCurrent(epoch)) return const AppSuccess<void>(null);
    final bundle = switch (bundleResult) {
      AppSuccess<VerifiedAsrModelBundle>(:final value) => value,
      AppError<VerifiedAsrModelBundle>() => null,
    };
    if (bundle == null) {
      return AppError<void>(
        (bundleResult as AppError<VerifiedAsrModelBundle>).failure,
      );
    }

    if (!_recognizerLoaded || bundle != _loadedBundle) {
      final loadResult = await _speechRecognizer.loadModel(bundle);
      if (!_isCurrent(epoch)) return const AppSuccess<void>(null);
      if (loadResult case AppError<void>(:final failure)) {
        _onUpdate(ObserverVoiceModelLoadFailed(failure));
        return AppError<void>(failure);
      }
      _recognizerLoaded = true;
      _loadedBundle = bundle;
    }

    final permission = await _permissionGateway.request();
    if (!_isCurrent(epoch)) return const AppSuccess<void>(null);
    if (permission case AppError<void>(:final failure)) {
      _onUpdate(ObserverVoiceInputFailed(failure: failure));
      return AppError<void>(failure);
    }

    final startResult = await _speechRecognizer.start();
    if (!_isCurrent(epoch)) {
      if (startResult case AppSuccess<SpeechRecognitionHandle>(:final value)) {
        final stopResult = await value.stop();
        if (stopResult is AppError<void>) {
          // A pause can invalidate start after native capture exists but
          // before this session publishes the handle. Retain failed teardown
          // ownership so the joining pause retries instead of crossing the
          // microphone-exclusion barrier while capture is still live.
          _recognitionHandle ??= value;
          return stopResult;
        }
      }
      return const AppSuccess<void>(null);
    }
    if (startResult case AppError<SpeechRecognitionHandle>(:final failure)) {
      _onUpdate(ObserverVoiceInputFailed(failure: failure));
      return AppError<void>(failure);
    }

    final handle = (startResult as AppSuccess<SpeechRecognitionHandle>).value;
    _recognitionHandle = handle;
    _mode = _VoiceInputMode.watching;
    _expectedSegmentId = 0;
    _recognitionSubscription = handle.events.listen(
      (event) => _queueRecognitionEvent(epoch, event),
      onError: (Object error, StackTrace stackTrace) {
        _queueUnexpectedRecognitionFailure(epoch, error, stackTrace);
      },
      onDone: () => _queueUnexpectedRecognitionClosure(epoch),
    );
    _onUpdate(const ObserverVoiceWatching());
    return const AppSuccess<void>(null);
  }

  Future<AppResult<VerifiedAsrModelBundle>> _resolveBundle() {
    final current = _modelStore.current;
    final artifact = current.artifact;
    if (current.phase == ModelStorePhase.ready && artifact != null) {
      return Future.value(AppSuccess(artifact));
    }
    return _modelStore.prepare();
  }

  void _ensureModelSubscription() {
    if (_modelSubscription != null) return;
    _onUpdate(ObserverVoiceModelStateChanged(_modelStore.current));
    _modelSubscription = _modelStore.states.listen((state) {
      if (!_closed) _onUpdate(ObserverVoiceModelStateChanged(state));
    });
  }

  // ── Streaming recognition policy ────────────────────────────────

  void _queueRecognitionEvent(int epoch, SpeechRecognitionEvent event) {
    _recognitionEventTask = (_recognitionEventTask ?? Future<void>.value()).then(
      (_) => _handleRecognitionEvent(epoch, event),
    );
  }

  Future<void> _handleRecognitionEvent(
    int epoch,
    SpeechRecognitionEvent event,
  ) async {
    if (!_isCurrent(epoch) || event.segmentId != _expectedSegmentId) return;
    switch (event) {
      case SpeechRecognitionHypothesis(:final transcript):
        await _handleHypothesis(epoch, transcript);
      case SpeechRecognitionEndpoint(:final transcript):
        await _handleEndpoint(epoch, transcript);
      case SpeechRecognitionFailure(:final failure):
        await _failActiveInput(epoch, failure);
    }
  }

  Future<void> _handleHypothesis(int epoch, String transcript) async {
    switch (_mode) {
      case _VoiceInputMode.idle:
        return;
      case _VoiceInputMode.watching:
        final match = _wakePhraseDetector.detect(transcript);
        if (match == null) return;
        final turnId = _beginTurn(match.trailingTranscript);
        _onUpdate(
          ObserverVoiceWakeDetected(
            turnId: turnId,
            trailingTranscript: _questionPrefix,
          ),
        );
        final reset = await _resetForListening(epoch);
        if (reset is AppError<void> || !_isCurrent(epoch)) return;
        _onUpdate(
          ObserverVoiceListeningStarted(
            turnId: turnId,
            transcript: _questionPrefix,
          ),
        );
      case _VoiceInputMode.listening:
        final turnId = _activeTurnId;
        if (turnId == null) return;
        _questionHypothesis = _normalizeTranscript(transcript);
        _onUpdate(
          ObserverVoiceTranscriptChanged(
            turnId: turnId,
            transcript: _assembledQuestion,
          ),
        );
    }
  }

  Future<void> _handleEndpoint(int epoch, String transcript) async {
    switch (_mode) {
      case _VoiceInputMode.idle:
        return;
      case _VoiceInputMode.watching:
        final match = _wakePhraseDetector.detect(transcript);
        if (match == null) {
          await _resetWatchingSegment(epoch);
          return;
        }
        final turnId = _beginTurn(match.trailingTranscript);
        _onUpdate(
          ObserverVoiceWakeDetected(
            turnId: turnId,
            trailingTranscript: _questionPrefix,
          ),
        );
        _onUpdate(
          ObserverVoiceListeningStarted(
            turnId: turnId,
            transcript: _questionPrefix,
          ),
        );
        await _completeQuestion(epoch, turnId, deadlineExpired: false);
      case _VoiceInputMode.listening:
        final turnId = _activeTurnId;
        if (turnId == null) return;
        _questionHypothesis = _normalizeTranscript(transcript);
        await _completeQuestion(epoch, turnId, deadlineExpired: false);
    }
  }

  int _beginTurn(String trailingTranscript) {
    final turnId = ++_turnSequence;
    _activeTurnId = turnId;
    _mode = _VoiceInputMode.listening;
    _questionPrefix = _normalizeTranscript(trailingTranscript);
    _questionHypothesis = '';
    _questionTimer = _deadlineFactory(_questionDeadline, () {
      _recognitionEventTask = (_recognitionEventTask ?? Future<void>.value()).then(
        (_) => _completeQuestion(_epoch, turnId, deadlineExpired: true),
      );
    });
    return turnId;
  }

  Future<AppResult<void>> _resetForListening(int epoch) async {
    final result = await _recognitionHandle!.resetForNextSegment();
    if (!_isCurrent(epoch)) return const AppSuccess<void>(null);
    if (result case AppError<void>(:final failure)) {
      await _failActiveInput(epoch, failure);
      return AppError<void>(failure);
    }
    _expectedSegmentId += 1;
    return const AppSuccess<void>(null);
  }

  Future<void> _resetWatchingSegment(int epoch) async {
    final result = await _recognitionHandle!.resetForNextSegment();
    if (!_isCurrent(epoch)) return;
    if (result case AppError<void>(:final failure)) {
      await _failActiveInput(epoch, failure);
      return;
    }
    _expectedSegmentId += 1;
  }

  Future<void> _completeQuestion(
    int epoch,
    int turnId, {
    required bool deadlineExpired,
  }) async {
    if (!_isCurrent(epoch) || _mode != _VoiceInputMode.listening || _activeTurnId != turnId) {
      return;
    }

    final question = _assembledQuestion;
    _cancelQuestionTimer();
    // Invalidate before stopping capture. Any endpoint already queued behind
    // this operation loses the epoch guard and cannot submit the turn again.
    _epoch += 1;
    _mode = _VoiceInputMode.idle;
    _activeTurnId = null;
    _questionPrefix = '';
    _questionHypothesis = '';
    final stopResult = await _detachAndStopRecognition();
    if (stopResult case AppError<void>(:final failure)) {
      _onUpdate(ObserverVoiceInputFailed(turnId: turnId, failure: failure));
      return;
    }
    if (question.isEmpty) {
      _onUpdate(
        ObserverVoiceInputFailed(
          turnId: turnId,
          failure: UnexpectedFailure(
            code: deadlineExpired ? 'voice_question_silence_timeout' : 'voice_question_empty',
          ),
        ),
      );
      return;
    }
    _onUpdate(
      ObserverVoiceQuestionCompleted(turnId: turnId, question: question),
    );
  }

  Future<void> _failActiveInput(int epoch, AppFailure failure) async {
    if (!_isCurrent(epoch)) return;
    final turnId = _activeTurnId;
    _cancelQuestionTimer();
    _epoch += 1;
    _mode = _VoiceInputMode.idle;
    _activeTurnId = null;
    _questionPrefix = '';
    _questionHypothesis = '';
    final stopResult = await _detachAndStopRecognition();
    final terminalFailure = switch (stopResult) {
      AppSuccess<void>() => failure,
      AppError<void>(:final failure) => failure,
    };
    _onUpdate(
      ObserverVoiceInputFailed(
        turnId: turnId,
        failure: terminalFailure,
      ),
    );
  }

  // ── Teardown and stale-result gates ─────────────────────────────

  Future<AppResult<void>> _pauseOnce() async {
    final activeWatch = _watchTask;
    if (activeWatch != null) await activeWatch;
    return _detachAndStopRecognition();
  }

  Future<AppResult<void>> _detachAndStopRecognition() async {
    final subscription = _recognitionSubscription;
    final handle = _recognitionHandle;
    _recognitionSubscription = null;
    await subscription?.cancel();
    if (handle == null) return const AppSuccess<void>(null);
    final result = await handle.stop();
    if (result is AppSuccess<void> && identical(_recognitionHandle, handle)) {
      _recognitionHandle = null;
    }
    return result;
  }

  Future<AppResult<void>> _suspendOnce() async {
    final pauseResult = await pause();
    final modelSuspendResult = await _suspendModelStore();
    final unloadResult = await _unloadRecognizer();
    return _firstFailure([
      pauseResult,
      modelSuspendResult,
      unloadResult,
    ]);
  }

  Future<AppResult<void>> _suspendModelStore() async {
    try {
      await _modelStore.suspend();
      return const AppSuccess<void>(null);
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(
        UnexpectedFailure(
          code: 'observer_voice_model_suspend_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<AppResult<void>> _unloadRecognizer() async {
    AppResult<void> result;
    try {
      result = await _speechRecognizer.unload();
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      result = AppError<void>(
        UnexpectedFailure(
          code: 'observer_voice_unload_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (result is AppSuccess<void>) {
      _recognizerLoaded = false;
      _loadedBundle = null;
    }
    return result;
  }

  Future<AppResult<void>> _closeOnce() async {
    final activeSuspend = _suspendTask;
    final suspendResult = activeSuspend == null ? const AppSuccess<void>(null) : await activeSuspend;
    final pauseResult = await pause();
    final recognitionEventTask = _recognitionEventTask;
    if (recognitionEventTask != null) await recognitionEventTask;
    await _modelSubscription?.cancel();
    _modelSubscription = null;
    return _firstFailure([suspendResult, pauseResult]);
  }

  void _queueUnexpectedRecognitionFailure(
    int epoch,
    Object error,
    StackTrace stackTrace,
  ) {
    _recognitionEventTask = (_recognitionEventTask ?? Future<void>.value()).then(
      (_) => _failActiveInput(
        epoch,
        UnexpectedFailure(
          code: 'voice_recognition_stream_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      ),
    );
  }

  void _queueUnexpectedRecognitionClosure(int epoch) {
    _recognitionEventTask = (_recognitionEventTask ?? Future<void>.value()).then((_) async {
      if (!_isCurrent(epoch) || _recognitionHandle == null) return;
      await _failActiveInput(
        epoch,
        const DeviceUnavailableFailure(
          code: 'voice_recognition_stream_closed',
        ),
      );
    });
  }

  bool _isCurrent(int epoch) => !_closed && epoch == _epoch;

  String get _assembledQuestion {
    return [_questionPrefix, _questionHypothesis].where((part) => part.isNotEmpty).join(' ').trim();
  }

  void _cancelQuestionTimer() {
    _questionTimer?.cancel();
    _questionTimer = null;
  }
}

enum _VoiceInputMode { idle, watching, listening }

String _normalizeTranscript(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

AppResult<void> _firstFailure(List<AppResult<void>> results) {
  for (final result in results) {
    if (result is AppError<void>) return result;
  }
  return const AppSuccess<void>(null);
}
