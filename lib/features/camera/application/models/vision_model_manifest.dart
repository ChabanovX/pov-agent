/// Pinned metadata for one platform-bundled YOLO artifact.
final class VisionModelManifest {
  /// Creates validated integrity metadata for a bundled model.
  factory VisionModelManifest({
    required String modelId,
    required String revision,
    required String assetPath,
    required int byteSize,
    required String sha256,
  }) {
    if (modelId.trim().isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'must not be empty');
    }
    if (revision.trim().isEmpty) {
      throw ArgumentError.value(revision, 'revision', 'must not be empty');
    }
    if (!assetPath.startsWith('assets/') || assetPath.endsWith('/')) {
      throw ArgumentError.value(
        assetPath,
        'assetPath',
        'must identify one bundled asset',
      );
    }
    if (byteSize <= 0) {
      throw ArgumentError.value(byteSize, 'byteSize', 'must be positive');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(
        sha256,
        'sha256',
        'must be a lowercase SHA-256 digest',
      );
    }
    return VisionModelManifest._(
      modelId: modelId,
      revision: revision,
      assetPath: assetPath,
      byteSize: byteSize,
      sha256: sha256,
    );
  }

  const VisionModelManifest._({
    required this.modelId,
    required this.revision,
    required this.assetPath,
    required this.byteSize,
    required this.sha256,
  });

  /// Model identifier expected by the native YOLO surface.
  final String modelId;

  /// Pinned packaging revision for receipt invalidation.
  final String revision;

  /// Flutter asset containing this platform's native model package.
  final String assetPath;

  /// Exact bundled artifact length.
  final int byteSize;

  /// Exact bundled artifact SHA-256 digest.
  final String sha256;
}
