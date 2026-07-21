import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pov_agent/features/assistant/data/ffi/llama_native_runtime.dart';

const _commandLoad = 'load';
const _commandGenerate = 'generate';
const _commandCancel = 'cancel';
const _commandUnload = 'unload';
const _commandClose = 'close';

const _eventReady = 'ready';
const _eventResponse = 'response';
const _eventToken = 'token';
const _eventGenerationComplete = 'generationComplete';
const _eventGenerationCancelled = 'generationCancelled';
const _eventGenerationError = 'generationError';

/// Native model-load result returned by [LlamaInferenceWorker].
final class LlamaWorkerLoadResult {
  /// Creates a load result containing the selected execution backend.
  const LlamaWorkerLoadResult({required this.usesGpu});

  /// Whether llama.cpp successfully offloaded the model to an accelerator.
  final bool usesGpu;
}

/// Coordinates terminal worker cleanup without losing retryable native state.
///
/// A failed native close keeps ownership in the worker isolate and clears the
/// active task so a later [close] call can retry. Port disposal starts only
/// after native destruction succeeds; once disposal begins, calls remain
/// joined because the native runtime no longer exists to retry.
final class LlamaWorkerShutdownCoordinator {
  /// Creates a coordinator around the worker's native and port boundaries.
  factory LlamaWorkerShutdownCoordinator({
    required Future<void> Function() closeNative,
    required Future<void> Function() dispose,
  }) {
    return LlamaWorkerShutdownCoordinator._(closeNative, dispose);
  }

  LlamaWorkerShutdownCoordinator._(this._closeNative, this._dispose);

  final Future<void> Function() _closeNative;
  final Future<void> Function() _dispose;

  Future<void>? _closeTask;
  bool _closing = false;
  bool _closed = false;

  /// Whether a terminal close currently owns the worker command boundary.
  bool get isClosing => _closing;

  /// Whether native destruction and worker-port disposal both completed.
  bool get isClosed => _closed;

  /// Closes native ownership before disposing the worker communication ports.
  Future<void> close() {
    final existing = _closeTask;
    if (existing != null) return existing;

    _closing = true;
    final task = _closeOnce();
    _closeTask = task;
    return task;
  }

  Future<void> _closeOnce() async {
    try {
      await _closeNative();
    } on Object {
      // Native destroy deliberately retains its opaque pointer on failure.
      // Keep the isolate reachable and let a later close retry that pointer.
      _closing = false;
      _closeTask = null;
      rethrow;
    }

    await _dispose();
    _closed = true;
    _closing = false;
  }
}

/// One active raw-byte generation owned by the inference worker.
abstract interface class LlamaWorkerGeneration {
  /// UTF-8 token fragments in decode order.
  ///
  /// A Unicode scalar may span adjacent fragments. Consumers must use a
  /// streaming decoder instead of decoding each event independently.
  Stream<Uint8List> get bytes;

  /// Settles after native generation stops and [bytes] closes.
  Future<void> get completion;

  /// Cooperatively stops native decoding and waits for it to settle.
  Future<void> cancel();
}

/// Worker boundary used by the llama-backed comment generator.
abstract interface class LlamaInferenceWorker {
  /// Loads one verified model, replacing any previously loaded runtime.
  Future<LlamaWorkerLoadResult> load(
    String modelPath,
    LlamaRuntimeConfiguration configuration,
  );

  /// Starts one generation. Overlapping generations are rejected.
  Future<LlamaWorkerGeneration> generate(
    String prompt,
    LlamaSamplingConfiguration sampling,
  );

  /// Cancels active generation and releases the loaded model.
  Future<void> unload();

  /// Permanently shuts down the worker isolate.
  ///
  /// A failed native destroy keeps the isolate reachable for another attempt.
  Future<void> close();
}

/// Persistent isolate that owns all synchronous llama.cpp work.
///
/// The isolate stays alive across requests so model memory does not cross an
/// isolate boundary and manual messages do not repeatedly reload the GGUF.
/// Commands are serialized by its event queue, while generation yields between
/// native token steps so cancellation can run. Request and generation IDs join
/// every terminal event to its owner. An isolate failure fails all outstanding
/// work and makes subsequent commands reject instead of writing to a dead port.
final class NativeLlamaInferenceWorker implements LlamaInferenceWorker {
  NativeLlamaInferenceWorker._(
    this._isolate,
    this._receivePort,
    this._errorPort,
    this._exitPort,
  ) {
    _shutdown = LlamaWorkerShutdownCoordinator(
      closeNative: _closeNative,
      dispose: _disposePorts,
    );
    _subscription = _receivePort.listen(_handleEvent);
    _errorSubscription = _errorPort.listen(_handleIsolateError);
    _exitSubscription = _exitPort.listen(_handleIsolateExit);
  }

  /// Spawns and handshakes with the persistent inference isolate.
  static Future<NativeLlamaInferenceWorker> spawn() async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    Isolate? isolate;
    NativeLlamaInferenceWorker? worker;
    try {
      isolate = await Isolate.spawn<SendPort>(
        _runLlamaWorker,
        receivePort.sendPort,
        debugName: 'pov-llama-inference',
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      worker = NativeLlamaInferenceWorker._(
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
  final Map<int, _NativeWorkerGeneration> _generations = {};

  late final LlamaWorkerShutdownCoordinator _shutdown;
  late final StreamSubscription<Object?> _subscription;
  late final StreamSubscription<Object?> _errorSubscription;
  late final StreamSubscription<Object?> _exitSubscription;

  var _nextRequestId = 1;
  var _nextGenerationId = 1;
  LlamaWorkerException? _terminalFailure;
  var _closed = false;

  @override
  Future<LlamaWorkerLoadResult> load(
    String modelPath,
    LlamaRuntimeConfiguration configuration,
  ) async {
    final activeGenerations = _activeCompletionFutures();
    final response = await _request([
      _commandLoad,
      modelPath,
      configuration.contextTokens,
      configuration.batchTokens,
      configuration.threadCount,
      configuration.gpuLayers,
    ]);
    await Future.wait(activeGenerations);
    return LlamaWorkerLoadResult(usesGpu: response == true);
  }

  @override
  Future<LlamaWorkerGeneration> generate(
    String prompt,
    LlamaSamplingConfiguration sampling,
  ) async {
    _ensureOpen();
    final generationId = _nextGenerationId++;
    final generation = _NativeWorkerGeneration(
      generationId,
      _cancelGeneration,
      () => _generations.remove(generationId),
    );
    _generations[generationId] = generation;

    try {
      await _request([
        _commandGenerate,
        generationId,
        prompt,
        sampling.maxTokens,
        sampling.temperature,
        sampling.topP,
        sampling.topK,
        sampling.minP,
        sampling.seed,
      ]);
      return generation;
    } on Object {
      _generations.remove(generationId);
      rethrow;
    }
  }

  @override
  Future<void> unload() async {
    if (_closed) return;
    final activeGenerations = _activeCompletionFutures();
    await _request([_commandUnload]);
    await Future.wait(activeGenerations);
  }

  @override
  Future<void> close() => _shutdown.close();

  Future<void> _closeNative() async {
    if (_closed || _terminalFailure != null) return;
    final activeGenerations = _activeCompletionFutures();
    await _request([_commandClose], allowWhileClosing: true);
    await Future.wait(activeGenerations);
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

  Future<void> _cancelGeneration(int generationId) async {
    if (_closed || !_generations.containsKey(generationId)) return;
    await _request([_commandCancel, generationId]);
    await _generations[generationId]?.completion;
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
        final int status,
        final String message,
      ]:
        _requests
            .remove(requestId)
            ?.completeError(
              LlamaWorkerException(status: status, message: message),
            );
      case [_eventToken, final int generationId, final Uint8List bytes]:
        _generations[generationId]?.add(bytes);
      case [_eventGenerationComplete, final int generationId]:
        final generation = _generations[generationId];
        if (generation != null) unawaited(generation.complete());
      case [_eventGenerationCancelled, final int generationId]:
        final generation = _generations[generationId];
        if (generation != null) unawaited(generation.complete());
      case [
        _eventGenerationError,
        final int generationId,
        final int status,
        final String message,
      ]:
        final generation = _generations[generationId];
        if (generation != null) {
          unawaited(
            generation.fail(
              LlamaWorkerException(status: status, message: message),
            ),
          );
        }
    }
  }

  void _handleIsolateError(Object? error) {
    final diagnostic = switch (error) {
      [final Object message, final Object stack] => '$message\n$stack',
      _ => '$error',
    };
    _recordTerminalFailure(
      LlamaWorkerException(
        status: -3,
        message: 'The inference isolate failed: $diagnostic',
      ),
    );
  }

  void _handleIsolateExit(Object? _) {
    if (_closed) return;
    _recordTerminalFailure(
      const LlamaWorkerException(
        status: -4,
        message: 'The inference isolate exited unexpectedly.',
      ),
    );
  }

  void _recordTerminalFailure(LlamaWorkerException failure) {
    _terminalFailure ??= failure;
    _failAll(_terminalFailure!);
  }

  void _failAll(LlamaWorkerException failure) {
    if (!_commandsReady.isCompleted) {
      _commandsReady.completeError(failure);
    }
    for (final request in _requests.values) {
      if (!request.isCompleted) request.completeError(failure);
    }
    _requests.clear();
    for (final generation in _generations.values.toList(growable: false)) {
      unawaited(generation.fail(failure));
    }
  }

  Future<void> _disposePorts() async {
    if (_closed) return;
    _closed = true;
    _failAll(
      _terminalFailure ??
          const LlamaWorkerException(
            status: -5,
            message: 'The inference worker is closed.',
          ),
    );
    await _subscription.cancel();
    await _errorSubscription.cancel();
    await _exitSubscription.cancel();
    _receivePort.close();
    _errorPort.close();
    _exitPort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  void _ensureOpen() => _ensureUsable();

  void _ensureUsable({bool allowWhileClosing = false}) {
    if (_closed) throw StateError('The inference worker is closed.');
    final terminalFailure = _terminalFailure;
    if (terminalFailure != null) throw terminalFailure;
    if (_shutdown.isClosing && !allowWhileClosing) {
      throw StateError('The inference worker is closing.');
    }
  }

  List<Future<void>> _activeCompletionFutures() {
    return _generations.values.map((generation) => generation.completion).toList(growable: false);
  }
}

/// Failure emitted by the native inference isolate boundary.
final class LlamaWorkerException implements Exception {
  /// Creates an exception with a stable bridge [status] and [message].
  const LlamaWorkerException({required this.status, required this.message});

  /// Native or worker status code.
  final int status;

  /// Diagnostic message suitable for logs.
  final String message;

  @override
  String toString() => 'LlamaWorkerException($status, $message)';
}

final class _NativeWorkerGeneration implements LlamaWorkerGeneration {
  _NativeWorkerGeneration(
    this.id,
    this._cancelNative,
    this._onSettled,
  ) {
    _bytes = StreamController<Uint8List>(
      onListen: () => _hasBytesListener = true,
    );
    // A generation can fail between the start response and the caller attaching
    // its completion listener. Keep that short handoff from surfacing as an
    // unhandled isolate error while preserving the error for later awaiters.
    _completion.future.ignore();
  }

  final int id;
  final Future<void> Function(int id) _cancelNative;
  final void Function() _onSettled;
  late final StreamController<Uint8List> _bytes;
  final Completer<void> _completion = Completer<void>();
  Future<void>? _cancelTask;
  Future<void>? _settlementTask;
  var _hasBytesListener = false;

  @override
  Stream<Uint8List> get bytes => _bytes.stream;

  @override
  Future<void> get completion => _completion.future;

  void add(Uint8List value) {
    if (_completion.isCompleted || _bytes.isClosed) return;
    _bytes.add(Uint8List.fromList(value));
  }

  Future<void> complete() {
    return _settlementTask ??= _settle();
  }

  Future<void> fail(Object error, [StackTrace? stackTrace]) {
    return _settlementTask ??= _settle(error, stackTrace);
  }

  Future<void> _settle([Object? error, StackTrace? stackTrace]) async {
    final closeTask = _bytes.close();
    if (_hasBytesListener) await closeTask;
    if (error == null) {
      _completion.complete();
    } else {
      _completion.completeError(error, stackTrace);
    }
    _onSettled();
  }

  @override
  Future<void> cancel() {
    return _cancelTask ??= _cancelNative(id);
  }
}

void _runLlamaWorker(SendPort events) {
  final commands = ReceivePort();
  final host = _LlamaWorkerHost(events);
  commands.listen(host.handle);
  events.send([_eventReady, commands.sendPort]);
}

final class _LlamaWorkerHost {
  _LlamaWorkerHost(this._events);

  final SendPort _events;
  LlamaNativeRuntime? _runtime;
  int? _activeGenerationId;

  void handle(Object? command) {
    switch (command) {
      case [
        _commandLoad,
        final int requestId,
        final String modelPath,
        final int contextTokens,
        final int batchTokens,
        final int threadCount,
        final int gpuLayers,
      ]:
        _load(
          requestId,
          modelPath,
          LlamaRuntimeConfiguration(
            contextTokens: contextTokens,
            batchTokens: batchTokens,
            threadCount: threadCount,
            gpuLayers: gpuLayers,
          ),
        );
      case [
        _commandGenerate,
        final int requestId,
        final int generationId,
        final String prompt,
        final int maxTokens,
        final double temperature,
        final double topP,
        final int topK,
        final double minP,
        final int seed,
      ]:
        _generate(
          requestId,
          generationId,
          prompt,
          LlamaSamplingConfiguration(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            minP: minP,
            seed: seed,
          ),
        );
      case [_commandCancel, final int requestId, final int generationId]:
        _cancel(requestId, generationId);
      case [_commandUnload, final int requestId]:
        _unload(requestId);
      case [_commandClose, final int requestId]:
        _unload(requestId);
    }
  }

  void _load(
    int requestId,
    String modelPath,
    LlamaRuntimeConfiguration configuration,
  ) {
    try {
      _cancelActive();
      final previousRuntime = _runtime;
      if (previousRuntime != null) {
        previousRuntime.close();
        _runtime = null;
      }
      final runtime = LlamaNativeRuntime.load(modelPath, configuration);
      _runtime = runtime;
      _respond(requestId, value: runtime.usesGpu);
    } on Object catch (error) {
      _respondError(requestId, error);
    }
  }

  void _generate(
    int requestId,
    int generationId,
    String prompt,
    LlamaSamplingConfiguration sampling,
  ) {
    final runtime = _runtime;
    if (runtime == null) {
      _respondError(
        requestId,
        const LlamaWorkerException(
          status: -6,
          message: 'The model is not loaded.',
        ),
      );
      return;
    }
    if (_activeGenerationId != null) {
      _respondError(
        requestId,
        const LlamaWorkerException(
          status: -7,
          message: 'A generation is already active.',
        ),
      );
      return;
    }

    try {
      runtime.begin(prompt, sampling);
      _activeGenerationId = generationId;
      _respond(requestId);
      unawaited(_pump(generationId, runtime));
    } on Object catch (error) {
      _respondError(requestId, error);
    }
  }

  Future<void> _pump(int generationId, LlamaNativeRuntime runtime) async {
    try {
      while (_activeGenerationId == generationId) {
        final step = runtime.next();
        switch (step) {
          case LlamaTokenBytes(:final bytes):
            if (_activeGenerationId == generationId && bytes.isNotEmpty) {
              _events.send([_eventToken, generationId, bytes]);
            }
          case LlamaGenerationComplete():
            if (_activeGenerationId == generationId) {
              _activeGenerationId = null;
              _events.send([_eventGenerationComplete, generationId]);
            }
            return;
        }

        // Native cancellation is cooperative between decode calls. Yielding to
        // the event queue lets a cancel command run before sampling continues.
        await Future<void>.delayed(Duration.zero);
      }
    } on Object catch (error) {
      if (_activeGenerationId != generationId) return;
      _activeGenerationId = null;
      final (status, message) = _failureDetails(error);
      _events.send([_eventGenerationError, generationId, status, message]);
    }
  }

  void _cancel(int requestId, int generationId) {
    try {
      if (_activeGenerationId == generationId) {
        _runtime?.cancel();
        _activeGenerationId = null;
        _events.send([_eventGenerationCancelled, generationId]);
      }
      _respond(requestId);
    } on Object catch (error) {
      _respondError(requestId, error);
    }
  }

  void _unload(int requestId) {
    try {
      _cancelActive();
      _runtime?.close();
      _runtime = null;
      _respond(requestId);
    } on Object catch (error) {
      _respondError(requestId, error);
    }
  }

  void _cancelActive() {
    final generationId = _activeGenerationId;
    if (generationId == null) return;
    _runtime?.cancel();
    _activeGenerationId = null;
    _events.send([_eventGenerationCancelled, generationId]);
  }

  void _respond(int requestId, {Object? value}) {
    _events.send([_eventResponse, requestId, true, value]);
  }

  void _respondError(int requestId, Object error) {
    final (status, message) = _failureDetails(error);
    _events.send([_eventResponse, requestId, false, status, message]);
  }
}

(int, String) _failureDetails(Object error) {
  return switch (error) {
    LlamaNativeException(:final status, :final message) => (status, message),
    LlamaWorkerException(:final status, :final message) => (status, message),
    _ => (-1, error.toString()),
  };
}
