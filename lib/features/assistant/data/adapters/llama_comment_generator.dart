import 'dart:async';
import 'dart:convert';

import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/application/services/first_complete_english_sentence_accumulator.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_reasoning_filter.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_inference_worker.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_native_runtime.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

const _llamaRandomSeedSentinel = 0xFFFFFFFF;

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
  ) : _nextShortGenerationSeed = _randomSeed;

  static final AppLogger _logger = AppLogger('LlamaCommentGenerator');

  final Future<LlamaInferenceWorker> Function() _createWorker;
  final LlamaRuntimeConfiguration _runtimeConfiguration;
  final int _randomSeed;
  int _nextShortGenerationSeed;

  Future<LlamaInferenceWorker>? _workerTask;
  Future<AppResult<void>>? _loadTask;
  VerifiedModelArtifact? _loadingArtifact;
  VerifiedModelArtifact? _loadedArtifact;
  bool? _loadedModelUsesGpu;
  String? _loadedModelBackendDiagnostic;
  bool? _lastUnloadSucceeded;
  _LlamaGenerationHandle? _activeGeneration;
  Future<void>? _closeTask;
  var _generationBusyRejections = 0;
  var _closed = false;

  /// Whether the currently loaded model uses the native GPU backend.
  ///
  /// This diagnostic is `null` while no model is loaded. Physical-device
  /// acceptance tests use it to reject CPU fallback on supported iOS devices.
  bool? get loadedModelUsesGpu => _loadedModelUsesGpu;

  /// Native explanation when loading selected a different execution backend.
  ///
  /// This stays null for an unmodified successful load and is cleared with the
  /// loaded model. It is diagnostic context rather than presentation copy.
  String? get loadedModelBackendDiagnostic => _loadedModelBackendDiagnostic;

  /// Whether the latest requested model unload completed without native error.
  ///
  /// This diagnostic is `null` before an unload or after a new load starts.
  /// Product-facing lifecycle remains normalized through [CommentGenerator].
  bool? get lastUnloadSucceeded => _lastUnloadSucceeded;

  /// Number of requests rejected because native generation was already active.
  ///
  /// Long-running acceptance lanes assert this remains zero. Product
  /// concurrency still enters through the normalized generation result.
  int get generationBusyRejections => _generationBusyRejections;

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
      _loadedModelUsesGpu = null;
      _loadedModelBackendDiagnostic = null;
      _lastUnloadSucceeded = null;
      worker = await _obtainWorker();
      final loadResult = await worker.load(
        artifact.filePath,
        _runtimeConfiguration,
      );
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
      _loadedModelUsesGpu = loadResult.usesGpu;
      _loadedModelBackendDiagnostic = loadResult.backendDiagnostic;
      return const AppSuccess<void>(null);
    } on Object catch (error, stackTrace) {
      _loadedArtifact = null;
      _loadedModelUsesGpu = null;
      _loadedModelBackendDiagnostic = null;
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
        _generationBusyRejections += 1;
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
      final seed = _seedFor(request.completionPolicy);
      final nativeGeneration = await worker.generate(
        request.prompt,
        LlamaSamplingConfiguration(
          maxTokens: request.options.maxTokens,
          temperature: request.options.temperature,
          topP: request.options.topP,
          topK: request.options.topK,
          minP: request.options.minP,
          seed: seed,
        ),
      );
      _advanceSeedAfterAcceptedStart(request.completionPolicy);
      late final _LlamaGenerationHandle handle;
      handle = _LlamaGenerationHandle(
        nativeGeneration,
        QwenReasoningFilter(
          startsInsideReasoning: request.startsInsideReasoning,
        ),
        request.completionPolicy,
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

  int _seedFor(GenerationCompletionPolicy completionPolicy) {
    if (completionPolicy != GenerationCompletionPolicy.firstSubstantiveEnglishSentence ||
        _randomSeed == _llamaRandomSeedSentinel) {
      return _randomSeed;
    }
    return _nextShortGenerationSeed;
  }

  void _advanceSeedAfterAcceptedStart(
    GenerationCompletionPolicy completionPolicy,
  ) {
    if (completionPolicy != GenerationCompletionPolicy.firstSubstantiveEnglishSentence ||
        _randomSeed == _llamaRandomSeedSentinel) {
      return;
    }
    // Reusing one explicit seed with an unchanged prompt can reproduce a
    // token-limit failure forever. A deterministic sequence preserves replay
    // while ensuring the next periodic short comment explores another sample.
    _nextShortGenerationSeed = _nextShortGenerationSeed == _llamaRandomSeedSentinel - 1
        ? 0
        : _nextShortGenerationSeed + 1;
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
      _loadedModelUsesGpu = null;
      _loadedModelBackendDiagnostic = null;
      _lastUnloadSucceeded = true;
    } on Object catch (error, stackTrace) {
      _loadedArtifact = null;
      _loadedModelUsesGpu = null;
      _loadedModelBackendDiagnostic = null;
      _lastUnloadSucceeded = false;
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
    final task = _closeRetriably();
    _closeTask = task;
    return task;
  }

  Future<void> _closeRetriably() async {
    try {
      await _closeOnce();
    } on Object {
      // The worker keeps native ownership after a failed destroy. Do not cache
      // that failed attempt: a later close must be able to reach it again.
      _closeTask = null;
      rethrow;
    }
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
      rethrow;
    } finally {
      _loadedArtifact = null;
      _loadedModelUsesGpu = null;
      _loadedModelBackendDiagnostic = null;
    }
  }
}

final class _LlamaGenerationHandle implements GenerationHandle {
  _LlamaGenerationHandle(
    this._native,
    this._filter,
    this._completionPolicy,
    this._onSettled,
  ) {
    unawaited(_forward());
  }

  final LlamaWorkerGeneration _native;
  final QwenReasoningFilter _filter;
  final GenerationCompletionPolicy _completionPolicy;
  final void Function() _onSettled;
  final StreamController<String> _chunks = StreamController<String>();
  final Completer<AppResult<String>> _completion = Completer<AppResult<String>>();
  final StringBuffer _visibleAnswer = StringBuffer();
  final FirstCompleteEnglishSentenceAccumulator _sentenceAccumulator = FirstCompleteEnglishSentenceAccumulator();
  Future<void>? _nativeCancelTask;
  Future<void>? _cancelTask;

  bool get isSettled => _completion.isCompleted;

  @override
  Stream<String> get chunks => _chunks.stream;

  @override
  Future<AppResult<String>> get completion => _completion.future;

  Future<void> _forward() async {
    final nativeCompletionOutcome = _captureFailure(_native.completion);
    _CapturedFailure? processingFailure;
    Future<_CapturedFailure?>? policyCancelOutcome;
    String? completedSentence;

    try {
      final decoded = const Utf8Decoder().bind(_native.bytes);
      await for (final chunk in decoded) {
        final visible = _filter.add(chunk);
        if (_completionPolicy == GenerationCompletionPolicy.firstSubstantiveEnglishSentence) {
          // Short-comment completion still commits only the validated first
          // sentence, but its reasoning-filtered prefix may be projected as a
          // disposable UI draft while native decoding is active.
          _publishPreview(visible);
          completedSentence = _sentenceAccumulator.add(visible);
          if (completedSentence != null) {
            // Observe cancellation immediately: leaving an await-for loop may
            // suspend while its stream subscription is being cancelled.
            policyCancelOutcome = _captureFailure(_requestNativeCancel());
            break;
          }
        } else {
          _publish(visible);
        }
      }
    } on Object catch (error, stackTrace) {
      processingFailure = (error: error, stackTrace: stackTrace);
      // Local decoding/filtering failures must not release single-flight
      // ownership while the native worker can still be generating.
      policyCancelOutcome ??= _captureFailure(_requestNativeCancel());
    }

    final policyCancelFailure = await policyCancelOutcome;
    final nativeCompletionFailure = await nativeCompletionOutcome;
    final terminalFailure = processingFailure ?? policyCancelFailure ?? nativeCompletionFailure;
    final AppResult<String> result;
    if (terminalFailure != null) {
      result = AppError<String>(
        _nativeFailure(
          code: 'assistant_generation',
          message: 'Local generation failed.',
          error: terminalFailure.error,
          stackTrace: terminalFailure.stackTrace,
        ),
      );
    } else {
      result = _finishSuccessfulForward(completedSentence);
    }

    // Completion must not depend on whether presentation subscribed to chunks.
    // A single-subscription controller's close future waits for a listener.
    unawaited(_chunks.close());
    if (!_completion.isCompleted) _completion.complete(result);
    _onSettled();
  }

  AppResult<String> _finishSuccessfulForward(String? completedSentence) {
    try {
      var sentence = completedSentence;
      final tail = _filter.finish();
      if (_completionPolicy == GenerationCompletionPolicy.firstSubstantiveEnglishSentence) {
        _publishPreview(tail);
        sentence ??= _sentenceAccumulator.add(tail);
        sentence ??= _sentenceAccumulator.finish();
        if (sentence == null) {
          return const AppError<String>(
            UnexpectedFailure(
              code: 'assistant_sentence_incomplete',
              message: 'The local model did not complete a short sentence.',
            ),
          );
        }
        return AppSuccess<String>(sentence);
      } else {
        _publish(tail);
      }
      return AppSuccess<String>(_visibleAnswer.toString());
    } on Object catch (error, stackTrace) {
      return AppError<String>(
        _nativeFailure(
          code: 'assistant_generation',
          message: 'Local generation failed.',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> _requestNativeCancel() {
    return _nativeCancelTask ??= Future<void>.sync(_native.cancel);
  }

  Future<_CapturedFailure?> _captureFailure(Future<void> operation) async {
    try {
      await operation;
      return null;
    } on Object catch (error, stackTrace) {
      return (error: error, stackTrace: stackTrace);
    }
  }

  void _publish(String chunk) {
    if (chunk.isEmpty || _chunks.isClosed) return;
    _visibleAnswer.write(chunk);
    _chunks.add(chunk);
  }

  void _publishPreview(String chunk) {
    if (chunk.isEmpty || _chunks.isClosed) return;
    _chunks.add(chunk);
  }

  @override
  Future<void> cancel() {
    return _cancelTask ??= _cancelAndWait();
  }

  Future<void> _cancelAndWait() async {
    try {
      await _requestNativeCancel();
    } on Object {
      // The normalized terminal result is published through completion.
    }
    await completion;
  }
}

typedef _CapturedFailure = ({Object error, StackTrace stackTrace});

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
