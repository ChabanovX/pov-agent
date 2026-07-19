import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A visible update from one [AssistantGenerationRunner] attempt.
sealed class AssistantGenerationUpdate {
  /// Creates an update belonging to [runId].
  const AssistantGenerationUpdate(this.runId);

  /// The generation attempt that produced this update.
  final int runId;
}

/// One non-empty visible answer fragment.
final class AssistantGenerationChunk extends AssistantGenerationUpdate {
  /// Creates a visible generation [chunk].
  const AssistantGenerationChunk({
    required int runId,
    required this.chunk,
  }) : super(runId);

  /// The next visible response fragment.
  final String chunk;
}

/// The normalized terminal result of one generation attempt.
final class AssistantGenerationCompleted extends AssistantGenerationUpdate {
  /// Creates a terminal generation update.
  const AssistantGenerationCompleted({
    required int runId,
    required this.result,
  }) : super(runId);

  /// The complete visible answer or normalized generation failure.
  final AppResult<String> result;
}

/// Owns the handle, chunk subscription, and task for one-at-a-time generation.
///
/// Cancellation invalidates a run before awaiting native cooperation. Normal
/// completion drains the chunk stream before publishing its terminal update,
/// so presentation never commits an answer ahead of already-delivered chunks.
/// The injected [CommentGenerator] remains app-owned and is not closed here.
final class AssistantGenerationRunner {
  /// Creates a runner that forwards visible updates to [onUpdate].
  factory AssistantGenerationRunner({
    required CommentGenerator commentGenerator,
    required void Function(AssistantGenerationUpdate update) onUpdate,
  }) {
    return AssistantGenerationRunner._(commentGenerator, onUpdate);
  }

  AssistantGenerationRunner._(this._commentGenerator, this._onUpdate);

  final CommentGenerator _commentGenerator;
  final void Function(AssistantGenerationUpdate update) _onUpdate;

  Future<void>? _runTask;
  StreamSubscription<String>? _chunkSubscription;
  GenerationHandle? _activeHandle;
  Future<void>? _closeTask;
  var _latestRunId = 0;
  var _closed = false;

  /// Whether a generation is starting, streaming, or being cancelled.
  bool get isActive => _runTask != null;

  /// Starts [request] if no other generation is active.
  ///
  /// Returns the new run identifier, or `null` when overlap is rejected.
  int? start(CommentGenerationRequest request) {
    if (_closed || isActive) return null;

    final runId = ++_latestRunId;
    late final Future<void> task;
    task = _run(runId, request).whenComplete(() {
      if (identical(_runTask, task)) _runTask = null;
    });
    _runTask = task;
    unawaited(task);
    return runId;
  }

  /// Invalidates and cooperatively stops the active generation.
  ///
  /// Concurrent callers share the same underlying run task through its slot.
  Future<void> cancel() async {
    if (!isActive) return;
    _latestRunId += 1;

    final handle = _activeHandle;
    try {
      if (handle != null) await handle.cancel();
    } finally {
      await _runTask;
    }

    final subscription = _chunkSubscription;
    if (subscription != null) await subscription.cancel();
    if (identical(_chunkSubscription, subscription)) {
      _chunkSubscription = null;
    }
    if (identical(_activeHandle, handle)) _activeHandle = null;
  }

  /// Stops the active run and permanently rejects new runs.
  Future<void> close() {
    final existingTask = _closeTask;
    if (existingTask != null) return existingTask;
    _closed = true;
    final task = cancel();
    _closeTask = task;
    return task;
  }

  Future<void> _run(
    int runId,
    CommentGenerationRequest request,
  ) async {
    AppResult<GenerationHandle> startResult;
    try {
      startResult = await _commentGenerator.generate(request);
    } on Object catch (error, stackTrace) {
      _publishTerminal(
        runId,
        AppError(
          UnexpectedFailure(
            code: 'assistant_generation_start_unexpected',
            message: error.toString(),
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
      return;
    }

    switch (startResult) {
      case AppError<GenerationHandle>(:final failure):
        _publishTerminal(runId, AppError(failure));
      case AppSuccess<GenerationHandle>(:final value):
        if (!_isCurrent(runId)) {
          await value.cancel();
          return;
        }
        await _consume(runId, value);
    }
  }

  Future<void> _consume(int runId, GenerationHandle handle) async {
    _activeHandle = handle;
    final subscription = handle.chunks.listen(
      (chunk) {
        if (_isCurrent(runId) && chunk.isNotEmpty) {
          _onUpdate(AssistantGenerationChunk(runId: runId, chunk: chunk));
        }
      },
    );
    final chunksDone = subscription.asFuture<void>();
    _chunkSubscription = subscription;

    AppResult<String> result;
    try {
      result = await handle.completion;
      // GenerationHandle promises to close chunks before completion settles.
      // Awaiting onDone also covers asynchronous StreamController delivery.
      await chunksDone;
    } on Object catch (error, stackTrace) {
      result = AppError(
        UnexpectedFailure(
          code: 'assistant_generation_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      await subscription.cancel();
      if (identical(_chunkSubscription, subscription)) {
        _chunkSubscription = null;
      }
      if (identical(_activeHandle, handle)) _activeHandle = null;
    }
    _publishTerminal(runId, result);
  }

  void _publishTerminal(int runId, AppResult<String> result) {
    if (_isCurrent(runId)) {
      _onUpdate(
        AssistantGenerationCompleted(runId: runId, result: result),
      );
    }
  }

  bool _isCurrent(int runId) {
    return !_closed && runId == _latestRunId;
  }
}
