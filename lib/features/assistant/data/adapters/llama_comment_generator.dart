import 'dart:async';
import 'dart:convert';

import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_reasoning_filter.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_inference_worker.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_native_runtime.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Owns the lazy llama.cpp worker and its currently loaded model.
///
/// Equivalent loads share one task. A new load first joins cancellation of the
/// active generation, and a failed load retires the worker so retry starts from
/// a clean native backend. Generation is single-flight. [unload] preserves the
/// worker isolate while freeing model memory; [close] is terminal and also
/// destroys the isolate.
final class LlamaCommentGenerator implements CommentGenerator {
  /// Creates a lazy generator with compile-time runtime parameters.
  factory LlamaCommentGenerator({
    required Future<LlamaInferenceWorker> Function() createWorker,
    required LlamaRuntimeConfiguration runtimeConfiguration,
    required int randomSeed,
  }) {
    return LlamaCommentGenerator._(
      createWorker,
      runtimeConfiguration,
      randomSeed,
    );
  }

  LlamaCommentGenerator._(
    this._createWorker,
    this._runtimeConfiguration,
    this._randomSeed,
  );

  static final AppLogger _logger = AppLogger('LlamaCommentGenerator');

  final Future<LlamaInferenceWorker> Function() _createWorker;
  final LlamaRuntimeConfiguration _runtimeConfiguration;
  final int _randomSeed;

  Future<LlamaInferenceWorker>? _workerTask;
  Future<AppResult<void>>? _loadTask;
  VerifiedModelArtifact? _loadingArtifact;
  VerifiedModelArtifact? _loadedArtifact;
  _LlamaGenerationHandle? _activeGeneration;
  Future<void>? _closeTask;
  var _closed = false;

  @override
  Future<AppResult<void>> loadModel(VerifiedModelArtifact artifact) async {
    if (_closed) {
      return const AppError<void>(
        DeviceUnavailableFailure(
          code: 'assistant_runtime_closed',
          message: 'The local assistant runtime is closed.',
        ),
      );
    }
    if (_loadedArtifact == artifact && _loadTask == null) {
      return const AppSuccess<void>(null);
    }

    final existingLoad = _loadTask;
    if (existingLoad != null) {
      if (_loadingArtifact == artifact) return existingLoad;
      await existingLoad;
      return loadModel(artifact);
    }

    _loadingArtifact = artifact;
    final task = _performLoad(artifact);
    _loadTask = task;
    try {
      return await task;
    } finally {
      if (identical(_loadTask, task)) {
        _loadTask = null;
        _loadingArtifact = null;
      }
    }
  }

  Future<AppResult<void>> _performLoad(VerifiedModelArtifact artifact) async {
    LlamaInferenceWorker? worker;
    try {
      await _activeGeneration?.cancel();
      _activeGeneration = null;
      worker = await _obtainWorker();
      await worker.load(artifact.filePath, _runtimeConfiguration);
      if (_closed) {
        await worker.unload();
        return const AppError<void>(
          DeviceUnavailableFailure(
            code: 'assistant_runtime_closed',
            message: 'The local assistant runtime closed while loading.',
          ),
        );
      }
      _loadedArtifact = artifact;
      return const AppSuccess<void>(null);
    } on Object catch (error, stackTrace) {
      _loadedArtifact = null;
      if (worker != null) await _retireWorkerAfterLoadFailure(worker);
      return AppError<void>(
        _nativeFailure(
          code: 'assistant_model_load',
          message: 'The verified local model could not be loaded.',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<LlamaInferenceWorker> _obtainWorker() async {
    final existing = _workerTask;
    if (existing != null) return existing;

    final task = _createWorker();
    _workerTask = task;
    try {
      return await task;
    } on Object {
      if (identical(_workerTask, task)) _workerTask = null;
      rethrow;
    }
  }

  Future<void> _retireWorkerAfterLoadFailure(
    LlamaInferenceWorker worker,
  ) async {
    _workerTask = null;
    try {
      await worker.close();
    } on Object catch (error, stackTrace) {
      _logger.e(
        'Failed to retire the native worker after model loading failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<AppResult<GenerationHandle>> generate(
    CommentGenerationRequest request,
  ) async {
    if (_closed) {
      return const AppError<GenerationHandle>(
        DeviceUnavailableFailure(
          code: 'assistant_runtime_closed',
          message: 'The local assistant runtime is closed.',
        ),
      );
    }
    final loadTask = _loadTask;
    if (loadTask != null) await loadTask;
    if (_loadedArtifact == null) {
      return const AppError<GenerationHandle>(
        DeviceUnavailableFailure(
          code: 'assistant_model_not_ready',
          message: 'A verified model must be loaded before generation.',
        ),
      );
    }
    if (_activeGeneration case final active?) {
      if (!active.isSettled) {
        return const AppError<GenerationHandle>(
          ValidationFailure(
            code: 'assistant_generation_busy',
            message: 'Only one local generation may run at a time.',
          ),
        );
      }
    }

    try {
      final worker = await _obtainWorker();
      final nativeGeneration = await worker.generate(
        request.prompt,
        LlamaSamplingConfiguration(
          maxTokens: request.options.maxTokens,
          temperature: request.options.temperature,
          topP: request.options.topP,
          topK: request.options.topK,
          minP: request.options.minP,
          seed: _randomSeed,
        ),
      );
      late final _LlamaGenerationHandle handle;
      handle = _LlamaGenerationHandle(
        nativeGeneration,
        QwenReasoningFilter(
          startsInsideReasoning: request.startsInsideReasoning,
        ),
        () {
          if (identical(_activeGeneration, handle)) {
            _activeGeneration = null;
          }
        },
      );
      _activeGeneration = handle;
      return AppSuccess<GenerationHandle>(handle);
    } on Object catch (error, stackTrace) {
      return AppError<GenerationHandle>(
        _nativeFailure(
          code: 'assistant_generation_start',
          message: 'Local generation could not start.',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> unload() async {
    if (_closed) return;
    try {
      await _loadTask;
      await _activeGeneration?.cancel();
      _activeGeneration = null;
      final workerTask = _workerTask;
      if (workerTask != null) await (await workerTask).unload();
      _loadedArtifact = null;
    } on Object catch (error, stackTrace) {
      _loadedArtifact = null;
      _logger.e(
        'Failed to unload the native model.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close() {
    final existing = _closeTask;
    if (existing != null) return existing;
    _closed = true;
    return _closeTask = _closeOnce();
  }

  Future<void> _closeOnce() async {
    try {
      await _loadTask;
      await _activeGeneration?.cancel();
      _activeGeneration = null;
      final workerTask = _workerTask;
      if (workerTask != null) await (await workerTask).close();
    } on Object catch (error, stackTrace) {
      _logger.e(
        'Failed to close the native assistant runtime.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _loadedArtifact = null;
    }
  }
}

final class _LlamaGenerationHandle implements GenerationHandle {
  _LlamaGenerationHandle(
    this._native,
    this._filter,
    this._onSettled,
  ) {
    unawaited(_forward());
  }

  final LlamaWorkerGeneration _native;
  final QwenReasoningFilter _filter;
  final void Function() _onSettled;
  final StreamController<String> _chunks = StreamController<String>();
  final Completer<AppResult<String>> _completion = Completer<AppResult<String>>();
  final StringBuffer _visibleAnswer = StringBuffer();
  Future<void>? _cancelTask;

  bool get isSettled => _completion.isCompleted;

  @override
  Stream<String> get chunks => _chunks.stream;

  @override
  Future<AppResult<String>> get completion => _completion.future;

  Future<void> _forward() async {
    AppResult<String> result;
    try {
      final decoded = const Utf8Decoder().bind(_native.bytes);
      await for (final chunk in decoded) {
        _publish(_filter.add(chunk));
      }
      await _native.completion;
      _publish(_filter.finish());
      result = AppSuccess<String>(_visibleAnswer.toString());
    } on Object catch (error, stackTrace) {
      result = AppError<String>(
        _nativeFailure(
          code: 'assistant_generation',
          message: 'Local generation failed.',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }

    // Completion must not depend on whether presentation subscribed to chunks.
    // A single-subscription controller's close future waits for a listener.
    unawaited(_chunks.close());
    if (!_completion.isCompleted) _completion.complete(result);
    _onSettled();
  }

  void _publish(String chunk) {
    if (chunk.isEmpty || _chunks.isClosed) return;
    _visibleAnswer.write(chunk);
    _chunks.add(chunk);
  }

  @override
  Future<void> cancel() {
    return _cancelTask ??= _cancelAndWait();
  }

  Future<void> _cancelAndWait() async {
    try {
      await _native.cancel();
    } on Object {
      // The normalized terminal result is published through completion.
    }
    await completion;
  }
}

DeviceUnavailableFailure _nativeFailure({
  required String code,
  required String message,
  required Object error,
  required StackTrace stackTrace,
}) {
  return DeviceUnavailableFailure(
    code: code,
    message: message,
    cause: error,
    stackTrace: stackTrace,
  );
}
