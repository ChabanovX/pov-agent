import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/services/assistant_generation_runner.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

/// Metadata retained while one automatic or manual generation is active.
sealed class ObserverActiveGeneration {
  const ObserverActiveGeneration(this.runId);

  /// Monotonic identifier assigned by the underlying generation runner.
  final int runId;

  /// Whether the run belongs to the timer or a manual prompt.
  ObserverGenerationKind get kind;

  /// The scene sampled for an automatic run.
  SceneSnapshot? get scene;
}

final class _AutomaticGeneration extends ObserverActiveGeneration {
  const _AutomaticGeneration(super.runId, this.scene);

  @override
  ObserverGenerationKind get kind => ObserverGenerationKind.automatic;

  @override
  final SceneSnapshot scene;
}

final class _ManualGeneration extends ObserverActiveGeneration {
  const _ManualGeneration(super.runId);

  @override
  ObserverGenerationKind get kind => ObserverGenerationKind.manual;

  @override
  SceneSnapshot? get scene => null;
}

/// A visible update tagged with its generation metadata.
sealed class ObserverGenerationUpdate {
  const ObserverGenerationUpdate(this.generation);

  /// The run that produced this update.
  final ObserverActiveGeneration generation;
}

/// A non-empty visible prefix from one active generation.
final class ObserverGenerationChunk extends ObserverGenerationUpdate {
  /// Creates a visible generation update.
  const ObserverGenerationChunk({
    required ObserverActiveGeneration generation,
    required this.chunk,
  }) : super(generation);

  /// The next visible response fragment.
  final String chunk;
}

/// The normalized terminal result of one active generation.
final class ObserverGenerationCompleted extends ObserverGenerationUpdate {
  /// Creates a terminal generation update.
  const ObserverGenerationCompleted({
    required ObserverActiveGeneration generation,
    required this.result,
  }) : super(generation);

  /// The completed visible text or normalized failure.
  final AppResult<String> result;
}

/// Owns one runner and its automatic-versus-manual run metadata.
///
/// Metadata remains active until the Bloc consumes completion. This closes the
/// small interval where native work has settled but its queued projection has
/// not, so a timer tick cannot overtake the previous committed comment.
final class ObserverGenerationSession {
  /// Creates an idle single-flight generation session.
  factory ObserverGenerationSession({
    required CommentGenerator commentGenerator,
    required void Function(ObserverGenerationUpdate update) onUpdate,
  }) {
    return ObserverGenerationSession._(commentGenerator, onUpdate);
  }

  ObserverGenerationSession._(
    CommentGenerator commentGenerator,
    this._onUpdate,
  ) {
    _runner = AssistantGenerationRunner(
      commentGenerator: commentGenerator,
      onUpdate: _forwardUpdate,
    );
  }

  final void Function(ObserverGenerationUpdate update) _onUpdate;
  late final AssistantGenerationRunner _runner;
  ObserverActiveGeneration? _active;

  /// The active run metadata, or `null` when the slot is available.
  ObserverActiveGeneration? get active => _active;

  /// Whether metadata or native runner work still occupies the slot.
  bool get isActive => _active != null || _runner.isActive;

  /// Starts an automatic run with its required sampled [scene].
  ObserverActiveGeneration? startAutomatic(
    CommentGenerationRequest request,
    SceneSnapshot scene,
  ) {
    if (isActive) return null;
    final runId = _runner.start(request);
    if (runId == null) return null;
    return _active = _AutomaticGeneration(runId, scene);
  }

  /// Starts a manual run without automatic scene metadata.
  ObserverActiveGeneration? startManual(CommentGenerationRequest request) {
    if (isActive) return null;
    final runId = _runner.start(request);
    if (runId == null) return null;
    return _active = _ManualGeneration(runId);
  }

  /// Releases metadata after the owner consumes [runId]'s completion.
  void complete(int runId) {
    if (_active?.runId == runId) _active = null;
  }

  /// Invalidates metadata before cooperatively stopping native work.
  Future<void> cancel() async {
    _active = null;
    await _runner.cancel();
  }

  /// Permanently closes the runner and active metadata slot.
  Future<void> close() async {
    _active = null;
    await _runner.close();
  }

  void _forwardUpdate(AssistantGenerationUpdate update) {
    final generation = _active;
    if (generation == null || generation.runId != update.runId) return;
    switch (update) {
      case AssistantGenerationChunk(:final chunk):
        _onUpdate(
          ObserverGenerationChunk(
            generation: generation,
            chunk: chunk,
          ),
        );
      case AssistantGenerationCompleted(:final result):
        _onUpdate(
          ObserverGenerationCompleted(
            generation: generation,
            result: result,
          ),
        );
    }
  }
}
