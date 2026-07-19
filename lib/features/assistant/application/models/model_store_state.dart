import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// The current phase of verified model preparation.
enum ModelStorePhase {
  /// No preparation has been requested.
  idle,

  /// The store is resolving and inspecting its local cache.
  loading,

  /// Model bytes are being transferred into an incomplete staging file.
  downloading,

  /// Local model bytes are being checked against the pinned manifest.
  verifying,

  /// A fully verified model artifact is available.
  ready,

  /// Preparation failed and may be retried.
  failure,

  /// Foreground work is paused and any active preparation has stopped.
  suspended,
}

/// The latest observable model-store state.
final class ModelStoreState {
  /// Creates the initial state.
  const ModelStoreState.idle() : phase = ModelStorePhase.idle, downloadProgress = null, artifact = null, failure = null;

  /// Creates the cache-resolution state.
  const ModelStoreState.loading()
    : phase = ModelStorePhase.loading,
      downloadProgress = null,
      artifact = null,
      failure = null;

  /// Creates a download state with normalized [progress].
  const ModelStoreState.downloading(double progress)
    : assert(
        progress >= 0 && progress <= 1,
        'Download progress must be in the range [0, 1].',
      ),
      phase = ModelStorePhase.downloading,
      downloadProgress = progress,
      artifact = null,
      failure = null;

  /// Creates the checksum-verification state.
  const ModelStoreState.verifying()
    : phase = ModelStorePhase.verifying,
      downloadProgress = null,
      artifact = null,
      failure = null;

  /// Creates a state containing the verified [artifact].
  factory ModelStoreState.ready(VerifiedModelArtifact artifact) {
    return ModelStoreState._(
      phase: ModelStorePhase.ready,
      artifact: artifact,
    );
  }

  /// Creates a recoverable model-preparation failure state.
  factory ModelStoreState.failure(AppFailure failure) {
    return ModelStoreState._(
      phase: ModelStorePhase.failure,
      failure: failure,
    );
  }

  /// Creates the foreground-suspended state.
  const ModelStoreState.suspended()
    : phase = ModelStorePhase.suspended,
      downloadProgress = null,
      artifact = null,
      failure = null;

  const ModelStoreState._({
    required this.phase,
    this.artifact,
    this.failure,
  }) : downloadProgress = null;

  /// The current preparation phase.
  final ModelStorePhase phase;

  /// Normalized download completion, present only while downloading.
  final double? downloadProgress;

  /// The verified artifact, present only when [phase] is ready.
  final VerifiedModelArtifact? artifact;

  /// The normalized failure, present only when [phase] is failure.
  final AppFailure? failure;
}
