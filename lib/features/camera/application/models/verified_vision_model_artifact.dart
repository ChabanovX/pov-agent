/// A platform-bundled YOLO artifact that passed integrity verification.
final class VerifiedVisionModelArtifact {
  /// Creates a verified vision artifact descriptor.
  const VerifiedVisionModelArtifact({
    required this.modelId,
    required this.revision,
    required this.assetPath,
    required this.byteSize,
    required this.sha256,
  });

  /// Native YOLO model identifier.
  final String modelId;

  /// Pinned packaging revision.
  final String revision;

  /// Verified Flutter asset path.
  final String assetPath;

  /// Verified artifact length.
  final int byteSize;

  /// Verified artifact digest.
  final String sha256;
}
