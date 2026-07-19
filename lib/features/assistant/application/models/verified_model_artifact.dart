import 'package:meta/meta.dart';

/// A local model file that has passed manifest size and checksum validation.
///
/// The application contract uses a string path so filesystem APIs remain in
/// data. Model-store implementations create artifacts only after real
/// verification.
@immutable
final class VerifiedModelArtifact {
  /// Creates metadata for one verified local model file.
  const VerifiedModelArtifact({
    required this.modelId,
    required this.revision,
    required this.filePath,
    required this.byteSize,
    required this.sha256,
  }) : assert(modelId != '', 'modelId must not be empty.'),
       assert(revision != '', 'revision must not be empty.'),
       assert(filePath != '', 'filePath must not be empty.'),
       assert(byteSize > 0, 'byteSize must be positive.'),
       assert(sha256 != '', 'sha256 must not be empty.');

  /// The stable model identifier from its pinned manifest.
  final String modelId;

  /// The exact upstream model revision that was verified.
  final String revision;

  /// The absolute platform path consumed by the native runtime adapter.
  final String filePath;

  /// The verified file length in bytes.
  final int byteSize;

  /// The lowercase SHA-256 digest verified by the model store.
  final String sha256;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VerifiedModelArtifact &&
            modelId == other.modelId &&
            revision == other.revision &&
            filePath == other.filePath &&
            byteSize == other.byteSize &&
            sha256 == other.sha256;
  }

  @override
  int get hashCode {
    return Object.hash(modelId, revision, filePath, byteSize, sha256);
  }
}
