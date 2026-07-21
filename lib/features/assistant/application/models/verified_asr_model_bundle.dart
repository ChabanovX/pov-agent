import 'package:meta/meta.dart';

/// A local streaming ASR bundle whose complete extracted tree was verified.
///
/// Paths remain strings so filesystem APIs stay in data. A bundle store may
/// construct this value only after archive and extracted-tree verification.
@immutable
final class VerifiedAsrModelBundle {
  /// Creates metadata for one verified local ASR model bundle.
  const VerifiedAsrModelBundle({
    required this.modelId,
    required this.revision,
    required this.bundleDirectoryPath,
    required this.modelFilePath,
    required this.tokensFilePath,
    required this.extractedByteSize,
    required this.extractedFileCount,
    required this.bundleTreeSha256,
  }) : assert(modelId != '', 'modelId must not be empty.'),
       assert(revision != '', 'revision must not be empty.'),
       assert(bundleDirectoryPath != '', 'bundleDirectoryPath must not be empty.'),
       assert(modelFilePath != '', 'modelFilePath must not be empty.'),
       assert(tokensFilePath != '', 'tokensFilePath must not be empty.'),
       assert(extractedByteSize > 0, 'extractedByteSize must be positive.'),
       assert(extractedFileCount > 0, 'extractedFileCount must be positive.'),
       assert(bundleTreeSha256 != '', 'bundleTreeSha256 must not be empty.');

  /// Stable ASR identifier from its pinned manifest.
  final String modelId;

  /// Exact upstream release or revision that was verified.
  final String revision;

  /// Absolute path to the published extracted bundle root.
  final String bundleDirectoryPath;

  /// Absolute path to the verified streaming CTC ONNX graph.
  final String modelFilePath;

  /// Absolute path to the verified token table.
  final String tokensFilePath;

  /// Verified sum of regular-file bytes in the bundle.
  final int extractedByteSize;

  /// Verified number of regular files in the bundle.
  final int extractedFileCount;

  /// Verified lowercase SHA-256 of the canonical bundle tree.
  final String bundleTreeSha256;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VerifiedAsrModelBundle &&
            modelId == other.modelId &&
            revision == other.revision &&
            bundleDirectoryPath == other.bundleDirectoryPath &&
            modelFilePath == other.modelFilePath &&
            tokensFilePath == other.tokensFilePath &&
            extractedByteSize == other.extractedByteSize &&
            extractedFileCount == other.extractedFileCount &&
            bundleTreeSha256 == other.bundleTreeSha256;
  }

  @override
  int get hashCode {
    return Object.hash(
      modelId,
      revision,
      bundleDirectoryPath,
      modelFilePath,
      tokensFilePath,
      extractedByteSize,
      extractedFileCount,
      bundleTreeSha256,
    );
  }
}
