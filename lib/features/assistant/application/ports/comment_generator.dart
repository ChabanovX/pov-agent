import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Generates local assistant text through a loaded native model runtime.
abstract interface class CommentGenerator {
  /// Loads the verified model into the local runtime.
  ///
  /// Concurrent calls for the same artifact share the active load. Loading a
  /// different artifact first unloads the current runtime safely.
  Future<AppResult<void>> loadModel(VerifiedModelArtifact artifact);

  /// Starts one generation, rejecting overlap through a normalized failure.
  Future<AppResult<GenerationHandle>> generate(
    CommentGenerationRequest request,
  );

  /// Cancels active generation and releases model and context handles.
  Future<void> unload();

  /// Cancels active work and permanently closes the runtime.
  ///
  /// Concurrent calls share one attempt. A failed native teardown retains
  /// ownership and may be retried; a successful close remains idempotent.
  Future<void> close();
}
