import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Resolves one pinned model into a verified local [TArtifact].
abstract interface class ModelStore<TArtifact extends Object> {
  /// The latest state, synchronously available to new consumers.
  ModelStoreState<TArtifact> get current;

  /// Model-preparation states in publication order.
  ///
  /// Implementations must expose a broadcast stream because process-level
  /// status and presentation may observe the same store.
  Stream<ModelStoreState<TArtifact>> get states;

  /// Resolves cache or downloads and verifies the configured model.
  ///
  /// Concurrent calls share the active preparation. A call after [suspend]
  /// begins a new foreground attempt, while a verified cache must be reused
  /// without network access.
  Future<AppResult<TArtifact>> prepare();

  /// Stops active foreground preparation without deleting verified cache.
  ///
  /// Completion means progress and preparation callbacks from the suspended
  /// attempt can no longer publish state.
  Future<void> suspend();

  /// Cancels preparation and closes the state stream exactly once.
  Future<void> close();
}

/// The verified single-file model store consumed by Qwen generation.
typedef QwenModelStore = ModelStore<VerifiedModelArtifact>;

/// The verified extracted-bundle store consumed by streaming ASR.
typedef AsrModelStore = ModelStore<VerifiedAsrModelBundle>;
