import 'package:meta/meta.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

/// The root-gate phase for the required on-device model pack.
enum ModelPackPhase {
  /// Local capacity and the installation receipt are being checked.
  checking,

  /// The device can install the pack and awaits explicit user intent.
  ready,

  /// One required model is being resolved, downloaded, or verified.
  installing,

  /// Active transfers are being stopped without deleting verified artifacts.
  cancelling,

  /// Every required model is verified and the application shell may open.
  complete,

  /// Setup is blocked by a recoverable preflight or model failure.
  failure,
}

/// The four product-facing roles in the required model pack.
enum ModelPackItemKind {
  /// Qwen generates comments and answers.
  assistant,

  /// YOLO detects stable scene objects.
  vision,

  /// Piper speaks completed responses.
  voice,

  /// Streaming ASR recognizes the wake phrase and questions.
  listening,
}

/// The visible preparation phase of one required model.
enum ModelPackItemPhase {
  /// The model has not started during this setup attempt.
  waiting,

  /// Local cache or extracted bundle metadata is being inspected.
  preparing,

  /// Model bytes are being transferred.
  downloading,

  /// Model bytes or an extracted bundle are being verified.
  verifying,

  /// The pinned artifact passed verification.
  verified,

  /// The item failed and setup remains blocked.
  failure,
}

/// Product metadata and current status for one required model.
@immutable
final class ModelPackItemState {
  /// Creates an immutable model-row state.
  const ModelPackItemState({
    required this.kind,
    required this.technicalName,
    required this.downloadBytes,
    required this.phase,
    this.progress,
    this.failure,
  });

  /// Stable role used to order and identify this row.
  final ModelPackItemKind kind;

  /// Pinned runtime or model name displayed as metadata.
  final String technicalName;

  /// Transfer bytes contributing to overall progress.
  final int downloadBytes;

  /// Current product-facing preparation phase.
  final ModelPackItemPhase phase;

  /// Normalized transfer progress while [phase] is downloading.
  final double? progress;

  /// Normalized failure while [phase] is failure.
  final AppFailure? failure;

  /// Returns this descriptor with a new preparation projection.
  ModelPackItemState withStatus({
    required ModelPackItemPhase phase,
    double? progress,
    AppFailure? failure,
  }) {
    return ModelPackItemState(
      kind: kind,
      technicalName: technicalName,
      downloadBytes: downloadBytes,
      phase: phase,
      progress: progress,
      failure: failure,
    );
  }
}

/// The mandatory setup state rendered above the application shell.
@immutable
final class ModelPackState {
  /// Creates a model-pack projection in fixed product order.
  ModelPackState({
    required this.phase,
    required Iterable<ModelPackItemState> items,
    this.availableStorageBytes,
    this.failure,
  }) : items = List<ModelPackItemState>.unmodifiable(items);

  /// Required free capacity before a full first installation begins.
  static const requiredStorageBytes = 1610612736;

  /// Current root-gate phase.
  final ModelPackPhase phase;

  /// Assistant, Vision, Voice, and Listening rows in product order.
  final List<ModelPackItemState> items;

  /// Most recently observed free capacity, when preflight succeeded.
  final int? availableStorageBytes;

  /// Root failure for storage, receipt, or active model preparation.
  final AppFailure? failure;

  /// Total network bytes described by the three downloadable manifests.
  int get totalDownloadBytes {
    return items.fold(0, (total, item) => total + item.downloadBytes);
  }

  /// Weighted progress across downloadable model artifacts.
  double get overallProgress {
    final total = totalDownloadBytes;
    if (total <= 0) return phase == ModelPackPhase.complete ? 1 : 0;
    var completed = 0.0;
    for (final item in items) {
      if (item.downloadBytes == 0) continue;
      final fraction = switch (item.phase) {
        ModelPackItemPhase.verified => 1.0,
        ModelPackItemPhase.verifying => 0.98,
        ModelPackItemPhase.downloading => item.progress ?? 0,
        _ => 0.0,
      };
      completed += item.downloadBytes * fraction;
    }
    return (completed / total).clamp(0, 1).toDouble();
  }

  /// The item currently performing setup work, if any.
  ModelPackItemState? get activeItem {
    for (final item in items) {
      if (item.phase == ModelPackItemPhase.preparing ||
          item.phase == ModelPackItemPhase.downloading ||
          item.phase == ModelPackItemPhase.verifying) {
        return item;
      }
    }
    return null;
  }

  /// Whether the shell may replace the setup gate.
  bool get isComplete => phase == ModelPackPhase.complete;

  /// Returns the row for [kind].
  ModelPackItemState item(ModelPackItemKind kind) {
    return items.firstWhere((item) => item.kind == kind);
  }

  /// Replaces one row without changing product order.
  ModelPackState replaceItem(
    ModelPackItemKind kind,
    ModelPackItemState replacement, {
    ModelPackPhase? phase,
    int? availableStorageBytes,
    bool retainAvailableStorage = true,
    AppFailure? failure,
    bool retainFailure = false,
  }) {
    return ModelPackState(
      phase: phase ?? this.phase,
      items: [
        for (final item in items)
          if (item.kind == kind) replacement else item,
      ],
      availableStorageBytes: retainAvailableStorage ? this.availableStorageBytes : availableStorageBytes,
      failure: retainFailure ? this.failure : failure,
    );
  }

  /// Returns a copy with root-level fields replaced.
  ModelPackState copyWith({
    ModelPackPhase? phase,
    Iterable<ModelPackItemState>? items,
    int? availableStorageBytes,
    bool retainAvailableStorage = true,
    AppFailure? failure,
    bool retainFailure = false,
  }) {
    return ModelPackState(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      availableStorageBytes: retainAvailableStorage ? this.availableStorageBytes : availableStorageBytes,
      failure: retainFailure ? this.failure : failure,
    );
  }
}
