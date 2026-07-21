import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pov_agent/features/assistant/application/models/asr_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _commandLoad = 'load';
const _commandStart = 'start';
const _commandAudio = 'audio';
const _commandReset = 'reset';
const _commandStop = 'stop';
const _commandUnload = 'unload';
const _commandClose = 'close';

const _eventReady = 'ready';
const _eventResponse = 'response';
const _eventHypothesis = 'hypothesis';
const _eventEndpoint = 'endpoint';

/// A non-programmer failure reported by the ASR worker boundary.
final class AsrWorkerException implements Exception {
  /// Creates a worker exception with a stable diagnostic [code].
  const AsrWorkerException({required this.code, required this.message});

  /// Stable failure identifier mapped before leaving data.
  final String code;

  /// Diagnostic detail that contains neither PCM nor transcript content.
  final String message;

  @override
  String toString() => 'AsrWorkerException($code, $message)';
}

/// A tagged worker event produced by one active native stream.
sealed class AsrWorkerEvent {
  const AsrWorkerEvent({
    required this.segmentId,
    required this.revision,
  });

  /// Zero-based stream segment advanced by explicit reset.
  final int segmentId;

  /// Monotonic event revision within one worker start/stop interval.
  final int revision;
}

/// A cumulative native transcript for the current stream segment.
final class AsrWorkerHypothesis extends AsrWorkerEvent {
  /// Creates a cumulative hypothesis.
  const AsrWorkerHypothesis({
    required super.segmentId,
    required super.revision,
    required this.transcript,
  });

  /// Full current transcript, not a token delta.
  final String transcript;
}

/// A native or maximum-duration endpoint for the current segment.
final class AsrWorkerEndpoint extends AsrWorkerEvent {
  /// Creates an endpoint captured before native reset.
  const AsrWorkerEndpoint({
    required super.segmentId,
    required super.revision,
    required this.transcript,
    required this.reason,
  });

  /// Final cumulative transcript for the segment.
  final String transcript;

  /// Why the segment ended.
  final SpeechRecognitionEndpointReason reason;
}

/// A terminal failure synthesized by the foreground worker boundary.
final class AsrWorkerFailure extends AsrWorkerEvent {
  /// Creates a tagged worker failure.
  const AsrWorkerFailure({
    required super.segmentId,
    required super.revision,
    required this.failure,
  });

  /// The worker failure to normalize in the enclosing data adapter.
  final AsrWorkerException failure;
}

/// Serial worker contract used by the microphone recognition adapter.
abstract interface class OnlineRecognitionWorker {
  /// Tagged recognition events from the active stream.
  Stream<AsrWorkerEvent> get events;

  /// Whether the worker isolate is gone and can no longer own native state.
  ///
  /// Foreground owners may finish local handle teardown in this state because
  /// there is no live isolate left to acknowledge [stop]. They must still call
  /// [close] to dispose the retained ports before replacing the worker.
  bool get isTerminallyUnavailable;

  /// Loads the verified model and native configuration.
  Future<void> load(
    VerifiedAsrModelBundle bundle,
    AsrRuntimeConfiguration configuration,
  );

  /// Creates a new online stream for live audio.
  Future<void> start();

  /// Queues one in-memory little-endian PCM16 chunk.
  Future<void> acceptAudio(Uint8List pcm16Bytes);

  /// Resets recognition and advances its segment tag.
  Future<void> reset();

  /// Drains queued audio and releases the active online stream.
  Future<void> stop();

  /// Stops recognition and releases the native model.
  Future<void> unload();

  /// Permanently shuts down the worker isolate.
  Future<void> close();
}

/// Coordinates terminal worker cleanup without losing retryable native state.
///
/// Native close runs before port disposal. If native destruction fails, the
/// isolate remains reachable and a subsequent [close] retries the same native
/// ownership instead of leaking it behind closed foreground ports.
final class AsrWorkerShutdownCoordinator {
  /// Creates a shutdown coordinator.
  factory AsrWorkerShutdownCoordinator({
    required Future<void> Function() closeNative,
    required Future<void> Function() dispose,
  }) {
    return AsrWorkerShutdownCoordinator._(closeNative, dispose);
  }

  AsrWorkerShutdownCoordinator._(this._closeNative, this._dispose);

  final Future<void> Function() _closeNative;
  final Future<void> Function() _dispose;

  Future<void>? _closeTask;
  var _closing = false;
  var _closed = false;

  /// Whether close currently owns the command boundary.
  bool get isClosing => _closing;

  /// Whether native destruction and foreground disposal both completed.
  bool get isClosed => _closed;

  /// Closes native ownership before communication resources.
  Future<void> close() {
    final activeTask = _closeTask;
    if (activeTask != null) return activeTask;
    if (_closed) return Future<void>.value();

    final task = _closeOnce();
    _closeTask = task;
    return task;
  }

  Future<void> _closeOnce() async {
    _closing = true;
    try {
      await _closeNative();
    } on Object {
      _closing = false;
      _closeTask = null;
      rethrow;
    }

    await _dispose();
    _closed = true;
    _closing = false;
  }
}

/// Persistent isolate that owns sherpa-onnx recognizer and stream pointers.
///
/// Model memory stays on one isolate across capture sessions. Foreground audio
/// commands carry [TransferableTypedData] and are bounded before they enter the
/// isolate queue. Start, reset, stop, unload, and close serialize against that
/// queue. Overflow fails the active stream deterministically and suppresses all
/// later native events until callers stop it. Native resources are always freed
/// stream-first, recognizer-second on their creation isolate.
final class SherpaOnlineRecognitionWorker implements OnlineRecognitionWorker {
  SherpaOnlineRecognitionWorker._(
    this._isolate,
    this._receivePort,
    this._errorPort,
    this._exitPort,
  ) {
    _shutdown = AsrWorkerShutdownCoordinator(
      closeNative: _closeNative,
      dispose: _disposePorts,
    );
    _eventSubscription = _receivePort.listen(_handleEvent);
    _errorSubscription = _errorPort.listen(_handleIsolateError);
    _exitSubscription = _exitPort.listen(_handleIsolateExit);
  }

  /// Spawns and handshakes with the persistent recognition isolate.
  static Future<SherpaOnlineRecognitionWorker> spawn() async {
    return _spawn(_runSherpaWorker, debugName: 'pov-sherpa-online-asr');
  }

  /// Spawns a protocol-compatible worker entry point for lifecycle tests.
  @visibleForTesting
  static Future<SherpaOnlineRecognitionWorker> spawnForTesting(
    FutureOr<void> Function(SendPort events) entryPoint,
  ) {
    return _spawn(entryPoint, debugName: 'pov-sherpa-online-asr-test');
  }

  static Future<SherpaOnlineRecognitionWorker> _spawn(
    FutureOr<void> Function(SendPort events) entryPoint, {
    required String debugName,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    Isolate? isolate;
    SherpaOnlineRecognitionWorker? worker;
    try {
      isolate = await Isolate.spawn<SendPort>(
        entryPoint,
        receivePort.sendPort,
        debugName: debugName,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      worker = SherpaOnlineRecognitionWorker._(
        isolate,
        receivePort,
        errorPort,
        exitPort,
      );
      await worker._commandsReady.future.timeout(const Duration(seconds: 10));
      return worker;
    } on Object {
      if (worker != null) {
        await worker._disposePorts();
      } else {
        isolate?.kill(priority: Isolate.immediate);
        receivePort.close();
        errorPort.close();
        exitPort.close();
      }
      rethrow;
    }
  }

  final Isolate _isolate;
  final ReceivePort _receivePort;
  final ReceivePort _errorPort;
  final ReceivePort _exitPort;
  final Completer<SendPort> _commandsReady = Completer<SendPort>();
  final Map<int, Completer<Object?>> _requests = {};
  final StreamController<AsrWorkerEvent> _events = StreamController<AsrWorkerEvent>.broadcast();
  final Set<Future<void>> _pendingAudioTasks = {};

  late final AsrWorkerShutdownCoordinator _shutdown;
  late final StreamSubscription<Object?> _eventSubscription;
  late final StreamSubscription<Object?> _errorSubscription;
  late final StreamSubscription<Object?> _exitSubscription;

  var _nextRequestId = 1;
  var _maxPendingAudioChunks = 1;
  var _segmentId = 0;
  var _lastRevision = 0;
  var _modelLoaded = false;
  var _streamActive = false;
  var _acceptingAudio = false;
  var _sessionFailed = false;
  var _closed = false;
  AsrWorkerException? _terminalFailure;

  @override
  Stream<AsrWorkerEvent> get events => _events.stream;

  @override
  bool get isTerminallyUnavailable => _terminalFailure != null;

  @override
  Future<void> load(
    VerifiedAsrModelBundle bundle,
    AsrRuntimeConfiguration configuration,
  ) async {
    _ensureUsable();
    _acceptingAudio = false;
    await _drainPendingAudio();
    // The isolate always unloads the previous model before attempting the new
    // constructor. A failed replacement is therefore never safe to start.
    _streamActive = false;
    _modelLoaded = false;
    await _request([_commandLoad, bundle, configuration]);
    _maxPendingAudioChunks = configuration.maxPendingAudioChunks;
    _modelLoaded = true;
    _streamActive = false;
    _sessionFailed = false;
  }

  @override
  Future<void> start() async {
    _ensureUsable();
    if (!_modelLoaded) {
      throw const AsrWorkerException(
        code: 'asr_model_not_loaded',
        message: 'The ASR model must be loaded before capture starts.',
      );
    }
    if (_streamActive) {
      throw const AsrWorkerException(
        code: 'asr_stream_busy',
        message: 'An ASR stream is already active.',
      );
    }

    await _request([_commandStart]);
    _segmentId = 0;
    _lastRevision = 0;
    _streamActive = true;
    _sessionFailed = false;
    _acceptingAudio = true;
  }

  @override
  Future<void> acceptAudio(Uint8List pcm16Bytes) {
    _ensureUsable();
    if (!_streamActive || !_acceptingAudio || pcm16Bytes.isEmpty) {
      return Future<void>.value();
    }
    if (_pendingAudioTasks.length >= _maxPendingAudioChunks) {
      _publishSessionFailure(
        const AsrWorkerException(
          code: 'asr_audio_backlog_overflow',
          message: 'Native decoding did not keep up with microphone capture.',
        ),
      );
      return Future<void>.value();
    }

    final transferred = TransferableTypedData.fromList([pcm16Bytes]);
    late final Future<void> task;
    task = _request([_commandAudio, transferred])
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (error is Error) {
              Error.throwWithStackTrace(error, stackTrace);
            }
            _publishSessionFailure(_asWorkerException(error));
          },
        )
        .whenComplete(() => _pendingAudioTasks.remove(task));
    _pendingAudioTasks.add(task);
    return task;
  }

  @override
  Future<void> reset() async {
    _ensureUsable();
    if (!_streamActive) {
      throw const AsrWorkerException(
        code: 'asr_stream_not_started',
        message: 'No active ASR stream can be reset.',
      );
    }
    if (_sessionFailed) {
      throw const AsrWorkerException(
        code: 'asr_stream_failed',
        message: 'A failed ASR stream must be stopped before restart.',
      );
    }

    // Stop accepting at the boundary so audio queued after the wake event
    // cannot be decoded into the segment that presentation is discarding.
    _acceptingAudio = false;
    await _drainPendingAudio();
    await _request([_commandReset]);
    _segmentId += 1;
    _acceptingAudio = true;
  }

  @override
  Future<void> stop() async {
    if (_closed || !_streamActive) return;
    _acceptingAudio = false;
    await _drainPendingAudio();
    await _request([_commandStop]);
    _streamActive = false;
    _sessionFailed = false;
  }

  @override
  Future<void> unload() async {
    if (_closed) return;
    _acceptingAudio = false;
    await _drainPendingAudio();
    await _request([_commandUnload]);
    _streamActive = false;
    _modelLoaded = false;
    _sessionFailed = false;
  }

  @override
  Future<void> close() => _shutdown.close();

  Future<void> _closeNative() async {
    if (_closed || _terminalFailure != null) return;
    _acceptingAudio = false;
    await _drainPendingAudio();
    await _request([_commandClose], allowWhileClosing: true);
    _streamActive = false;
    _modelLoaded = false;
  }

  Future<Object?> _request(
    List<Object?> payload, {
    bool allowWhileClosing = false,
  }) async {
    _ensureUsable(allowWhileClosing: allowWhileClosing);
    final commands = await _commandsReady.future;
    _ensureUsable(allowWhileClosing: allowWhileClosing);
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _requests[requestId] = completer;
    commands.send([payload.first, requestId, ...payload.skip(1)]);
    return completer.future;
  }

  Future<void> _drainPendingAudio() async {
    while (_pendingAudioTasks.isNotEmpty) {
      await Future.wait(_pendingAudioTasks.toList(growable: false));
    }
  }

  void _handleEvent(Object? event) {
    switch (event) {
      case [_eventReady, final SendPort commands]:
        if (!_commandsReady.isCompleted) _commandsReady.complete(commands);
      case [_eventResponse, final int requestId, true, final Object? value]:
        _requests.remove(requestId)?.complete(value);
      case [
        _eventResponse,
        final int requestId,
        false,
        final String code,
        final String message,
      ]:
        _requests.remove(requestId)?.completeError(AsrWorkerException(code: code, message: message));
      case [
        _eventHypothesis,
        final int segmentId,
        final int revision,
        final String transcript,
      ]:
        if (!_sessionFailed && _streamActive) {
          _segmentId = segmentId;
          _lastRevision = revision;
          _events.add(
            AsrWorkerHypothesis(
              segmentId: segmentId,
              revision: revision,
              transcript: transcript,
            ),
          );
        }
      case [
        _eventEndpoint,
        final int segmentId,
        final int revision,
        final String transcript,
        final String reasonName,
      ]:
        if (!_sessionFailed && _streamActive) {
          _segmentId = segmentId;
          _lastRevision = revision;
          _acceptingAudio = false;
          _events.add(
            AsrWorkerEndpoint(
              segmentId: segmentId,
              revision: revision,
              transcript: transcript,
              reason: SpeechRecognitionEndpointReason.values.byName(
                reasonName,
              ),
            ),
          );
        }
    }
  }

  void _publishSessionFailure(AsrWorkerException failure) {
    if (_sessionFailed || !_streamActive) return;
    _sessionFailed = true;
    _acceptingAudio = false;
    _lastRevision += 1;
    _events.add(
      AsrWorkerFailure(
        segmentId: _segmentId,
        revision: _lastRevision,
        failure: failure,
      ),
    );
  }

  void _handleIsolateError(Object? error) {
    final diagnostic = switch (error) {
      [final Object message, final Object stack] => '$message\n$stack',
      _ => '$error',
    };
    _recordTerminalFailure(
      AsrWorkerException(
        code: 'asr_worker_isolate_failed',
        message: 'The ASR isolate failed: $diagnostic',
      ),
    );
  }

  void _handleIsolateExit(Object? _) {
    if (_closed) return;
    _recordTerminalFailure(
      const AsrWorkerException(
        code: 'asr_worker_isolate_exited',
        message: 'The ASR isolate exited unexpectedly.',
      ),
    );
  }

  void _recordTerminalFailure(AsrWorkerException failure) {
    _terminalFailure ??= failure;
    _publishSessionFailure(_terminalFailure!);
    _failAllRequests(_terminalFailure!);
  }

  void _failAllRequests(AsrWorkerException failure) {
    if (!_commandsReady.isCompleted) _commandsReady.completeError(failure);
    for (final request in _requests.values) {
      if (!request.isCompleted) request.completeError(failure);
    }
    _requests.clear();
  }

  Future<void> _disposePorts() async {
    if (_closed) return;
    _closed = true;
    _failAllRequests(
      _terminalFailure ??
          const AsrWorkerException(
            code: 'asr_worker_closed',
            message: 'The ASR worker is closed.',
          ),
    );
    await _eventSubscription.cancel();
    await _errorSubscription.cancel();
    await _exitSubscription.cancel();
    await _events.close();
    _receivePort.close();
    _errorPort.close();
    _exitPort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  void _ensureUsable({bool allowWhileClosing = false}) {
    if (_closed) throw StateError('The ASR worker is closed.');
    final terminalFailure = _terminalFailure;
    if (terminalFailure != null) throw terminalFailure;
    if (_shutdown.isClosing && !allowWhileClosing) {
      throw StateError('The ASR worker is closing.');
    }
  }
}

AsrWorkerException _asWorkerException(Object error) {
  if (error case final AsrWorkerException workerError) return workerError;
  return AsrWorkerException(
    code: 'asr_worker_request_failed',
    message: error.toString(),
  );
}

/// Stateful little-endian PCM16 decoder used inside the native isolate.
///
/// Plugin chunk boundaries are not assumed to align to a 16-bit sample. One
/// trailing low byte is carried into the next chunk and rejected only when the
/// stream is finalized with a genuinely truncated sample.
final class Pcm16LittleEndianDecoder {
  int? _pendingLowByte;

  /// Converts the next byte chunk to normalized mono float samples.
  Float32List decode(Uint8List bytes) {
    final availableBytes = bytes.length + (_pendingLowByte == null ? 0 : 1);
    final samples = Float32List(availableBytes ~/ 2);
    var byteIndex = 0;
    var sampleIndex = 0;

    final pendingLowByte = _pendingLowByte;
    if (pendingLowByte != null && bytes.isNotEmpty) {
      samples[sampleIndex++] = _normalize(pendingLowByte, bytes[byteIndex++]);
      _pendingLowByte = null;
    }

    while (byteIndex + 1 < bytes.length) {
      samples[sampleIndex++] = _normalize(
        bytes[byteIndex],
        bytes[byteIndex + 1],
      );
      byteIndex += 2;
    }
    if (byteIndex < bytes.length) _pendingLowByte = bytes[byteIndex];
    return samples;
  }

  /// Rejects a truncated final sample.
  void finish() {
    if (_pendingLowByte != null) {
      throw const AsrWorkerException(
        code: 'asr_pcm_truncated_sample',
        message: 'The PCM16 stream ended with one unmatched byte.',
      );
    }
  }

  /// Discards carried byte state at an explicit segment boundary.
  void reset() {
    _pendingLowByte = null;
  }
}

double _normalize(int lowByte, int highByte) {
  var sample = lowByte | (highByte << 8);
  if (sample >= 0x8000) sample -= 0x10000;
  return sample / 32768.0;
}

Future<void> _runSherpaWorker(SendPort events) async {
  final commands = ReceivePort();
  final runtime = _SherpaOnlineRuntime(events);
  events.send([_eventReady, commands.sendPort]);

  await commands.forEach(runtime.handle);
}

final class _SherpaOnlineRuntime {
  _SherpaOnlineRuntime(this._events);

  final SendPort _events;
  final Pcm16LittleEndianDecoder _pcmDecoder = Pcm16LittleEndianDecoder();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  AsrRuntimeConfiguration? _configuration;
  var _segmentId = 0;
  var _revision = 0;
  var _acceptedSampleCount = 0;
  var _lastTranscript = '';
  var _awaitingReset = false;

  void handle(Object? command) {
    if (command case [final String name, final int requestId, ...]) {
      try {
        switch (command) {
          case [
            _commandLoad,
            _,
            final VerifiedAsrModelBundle bundle,
            final AsrRuntimeConfiguration configuration,
          ]:
            _load(bundle, configuration);
          case [_commandStart, _]:
            _start();
          case [_commandAudio, _, final TransferableTypedData transferred]:
            _acceptAudio(transferred.materialize().asUint8List());
          case [_commandReset, _]:
            _reset();
          case [_commandStop, _]:
            _stop();
          case [_commandUnload, _]:
            _unload();
          case [_commandClose, _]:
            _unload();
          case _:
            throw AsrWorkerException(
              code: 'asr_worker_invalid_command',
              message: 'Unknown ASR worker command: $name.',
            );
        }
        _events.send([_eventResponse, requestId, true, null]);
      } on Object catch (error) {
        if (error is Error) rethrow;
        final failure = _asWorkerException(error);
        _events.send([
          _eventResponse,
          requestId,
          false,
          failure.code,
          failure.message,
        ]);
      }
    }
  }

  void _load(
    VerifiedAsrModelBundle bundle,
    AsrRuntimeConfiguration configuration,
  ) {
    _unload();
    sherpa.initBindings();
    _recognizer = sherpa.OnlineRecognizer(
      buildSherpaOnlineRecognizerConfiguration(bundle, configuration),
    );
    _configuration = configuration;
  }

  void _start() {
    if (_stream != null) {
      throw const AsrWorkerException(
        code: 'asr_stream_busy',
        message: 'An online stream is already active.',
      );
    }
    final recognizer = _recognizer;
    if (recognizer == null || _configuration == null) {
      throw const AsrWorkerException(
        code: 'asr_model_not_loaded',
        message: 'The ASR model must be loaded before stream creation.',
      );
    }
    _stream = recognizer.createStream();
    _segmentId = 0;
    _revision = 0;
    _clearSegmentState();
  }

  void _acceptAudio(Uint8List bytes) {
    if (_awaitingReset) return;
    final recognizer = _requireRecognizer();
    final stream = _requireStream();
    final configuration = _configuration!;
    final samples = _pcmDecoder.decode(bytes);
    if (samples.isEmpty) return;

    stream.acceptWaveform(
      samples: samples,
      sampleRate: configuration.sampleRateHz,
    );
    _acceptedSampleCount += samples.length;
    _drainReadyFrames(recognizer, stream);
    _publishChangedHypothesis(recognizer, stream);

    final reachedMaximum = _acceptedSampleCount >= _maximumSegmentSamples(configuration);
    if (reachedMaximum || recognizer.isEndpoint(stream)) {
      _awaitingReset = true;
      _revision += 1;
      final reason = reachedMaximum
          ? SpeechRecognitionEndpointReason.maximumDuration
          : SpeechRecognitionEndpointReason.trailingSilence;
      _events.send([
        _eventEndpoint,
        _segmentId,
        _revision,
        _lastTranscript,
        reason.name,
      ]);
    }
  }

  void _reset() {
    final recognizer = _requireRecognizer();
    final stream = _requireStream();
    recognizer.reset(stream);
    _segmentId += 1;
    _clearSegmentState();
  }

  void _stop() {
    final stream = _stream;
    if (stream == null) return;
    final recognizer = _requireRecognizer();
    final endpointAlreadyPublished = _awaitingReset;

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      _pcmDecoder.finish();
      stream.inputFinished();
      _drainReadyFrames(recognizer, stream);
      // An endpoint is the terminal event for its segment. Native
      // finalization may refine the result, but publishing that refinement
      // after the endpoint would violate the event ordering contract.
      if (!endpointAlreadyPublished) {
        _publishChangedHypothesis(recognizer, stream);
      }
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    try {
      stream.free();
      _stream = null;
      _clearSegmentState();
    } on Object catch (error, stackTrace) {
      failure = AsrWorkerException(
        code: 'asr_stream_free_failed',
        message: failure == null
            ? 'Native online-stream destruction failed: $error'
            : 'Stream finalization failed, then native stream destruction '
                  'also failed: $error',
      );
      failureStackTrace = stackTrace;
    }

    final terminalFailure = failure;
    if (terminalFailure != null) {
      Error.throwWithStackTrace(
        terminalFailure,
        failureStackTrace ?? StackTrace.current,
      );
    }
  }

  void _unload() {
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      _stop();
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    // The recognizer cannot be destroyed while it may still own a live
    // stream. A later unload retries stream destruction first.
    if (_stream == null) {
      final recognizer = _recognizer;
      if (recognizer != null) {
        try {
          recognizer.free();
          _recognizer = null;
          _configuration = null;
        } on Object catch (error, stackTrace) {
          failure = AsrWorkerException(
            code: 'asr_recognizer_free_failed',
            message: failure == null
                ? 'Native online-recognizer destruction failed: $error'
                : 'Stream cleanup failed, then native recognizer destruction '
                      'also failed: $error',
          );
          failureStackTrace = stackTrace;
        }
      } else {
        _configuration = null;
      }
    }

    final terminalFailure = failure;
    if (terminalFailure != null) {
      Error.throwWithStackTrace(
        terminalFailure,
        failureStackTrace ?? StackTrace.current,
      );
    }
  }

  void _drainReadyFrames(
    sherpa.OnlineRecognizer recognizer,
    sherpa.OnlineStream stream,
  ) {
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
  }

  void _publishChangedHypothesis(
    sherpa.OnlineRecognizer recognizer,
    sherpa.OnlineStream stream,
  ) {
    final transcript = recognizer.getResult(stream).text;
    if (transcript == _lastTranscript) return;
    _lastTranscript = transcript;
    _revision += 1;
    _events.send([
      _eventHypothesis,
      _segmentId,
      _revision,
      transcript,
    ]);
  }

  sherpa.OnlineRecognizer _requireRecognizer() {
    final recognizer = _recognizer;
    if (recognizer != null) return recognizer;
    throw const AsrWorkerException(
      code: 'asr_model_not_loaded',
      message: 'The native ASR recognizer is not loaded.',
    );
  }

  sherpa.OnlineStream _requireStream() {
    final stream = _stream;
    if (stream != null) return stream;
    throw const AsrWorkerException(
      code: 'asr_stream_not_started',
      message: 'The native ASR stream is not active.',
    );
  }

  void _clearSegmentState() {
    _pcmDecoder.reset();
    _acceptedSampleCount = 0;
    _lastTranscript = '';
    _awaitingReset = false;
  }
}

int _maximumSegmentSamples(AsrRuntimeConfiguration configuration) {
  return configuration.sampleRateHz *
      configuration.maxUtteranceDuration.inMicroseconds ~/
      Duration.microsecondsPerSecond;
}

/// Builds the pure sherpa configuration for the selected NeMo streaming CTC model.
@visibleForTesting
sherpa.OnlineRecognizerConfig buildSherpaOnlineRecognizerConfiguration(
  VerifiedAsrModelBundle bundle,
  AsrRuntimeConfiguration configuration,
) {
  return sherpa.OnlineRecognizerConfig(
    feat: sherpa.FeatureConfig(
      sampleRate: configuration.sampleRateHz,
      featureDim: configuration.featureDimension,
    ),
    model: sherpa.OnlineModelConfig(
      nemoCtc: sherpa.OnlineNemoCtcModelConfig(
        model: bundle.modelFilePath,
      ),
      tokens: bundle.tokensFilePath,
      numThreads: configuration.threadCount,
      provider: configuration.provider,
      debug: configuration.debug,
    ),
    decodingMethod: configuration.decodingMethod,
    maxActivePaths: configuration.maxActivePaths,
    rule1MinTrailingSilence: configuration.rule1MinTrailingSilence.inMicroseconds / Duration.microsecondsPerSecond,
    rule2MinTrailingSilence: configuration.rule2MinTrailingSilence.inMicroseconds / Duration.microsecondsPerSecond,
    rule3MinUtteranceLength: configuration.maxUtteranceDuration.inMicroseconds / Duration.microsecondsPerSecond,
  );
}
