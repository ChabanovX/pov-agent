import 'package:pov_agent/features/assistant/data/models/verified_archive_model_manifest.dart';

/// Immutable acquisition and integrity metadata for one Piper voice bundle.
final class PiperModelManifest implements VerifiedArchiveModelManifest {
  /// Creates and validates an injectable Piper bundle manifest.
  factory PiperModelManifest({
    required String modelId,
    required String downloadUrl,
    required String revision,
    required String archiveFilename,
    required int archiveByteSize,
    required String archiveSha256,
    required int expandedArchiveByteSize,
    required int extractedByteSize,
    required int extractedFileCount,
    required String bundleTreeSha256,
    required String archiveRoot,
    required String modelFilename,
    required String tokensFilename,
    required String espeakDataDirectory,
    required String license,
    required int downloadReserveBytes,
  }) {
    final uri = VerifiedArchiveManifestValidation.networkUri(
      downloadUrl,
      name: 'downloadUrl',
      label: 'The Piper URL',
    );
    VerifiedArchiveManifestValidation.nonEmpty(
      modelId,
      name: 'modelId',
      label: 'The Piper model ID',
    );
    VerifiedArchiveManifestValidation.nonEmpty(
      revision,
      name: 'revision',
      label: 'The Piper revision',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      archiveFilename,
      name: 'archiveFilename',
      label: 'The Piper archive filename',
    );
    VerifiedArchiveManifestValidation.positive(
      archiveByteSize,
      name: 'archiveByteSize',
      label: 'The Piper archive byte size',
    );
    VerifiedArchiveManifestValidation.sha256(
      archiveSha256,
      name: 'archiveSha256',
      label: 'The Piper archive SHA-256',
    );
    VerifiedArchiveManifestValidation.positive(
      expandedArchiveByteSize,
      name: 'expandedArchiveByteSize',
      label: 'The Piper expanded archive byte size',
    );
    VerifiedArchiveManifestValidation.positive(
      extractedByteSize,
      name: 'extractedByteSize',
      label: 'The Piper extracted byte size',
    );
    VerifiedArchiveManifestValidation.positive(
      extractedFileCount,
      name: 'extractedFileCount',
      label: 'The Piper extracted file count',
    );
    VerifiedArchiveManifestValidation.sha256(
      bundleTreeSha256,
      name: 'bundleTreeSha256',
      label: 'The Piper bundle tree SHA-256',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      archiveRoot,
      name: 'archiveRoot',
      label: 'The Piper archive root',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      modelFilename,
      name: 'modelFilename',
      label: 'The Piper model filename',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      tokensFilename,
      name: 'tokensFilename',
      label: 'The Piper tokens filename',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      espeakDataDirectory,
      name: 'espeakDataDirectory',
      label: 'The Piper eSpeak data directory',
    );
    VerifiedArchiveManifestValidation.distinctPathComponents(
      [archiveFilename, archiveRoot],
      label: 'The Piper archive filename and extracted root',
    );
    VerifiedArchiveManifestValidation.distinctPathComponents(
      [modelFilename, tokensFilename, espeakDataDirectory],
      label: 'The Piper model, tokens, and eSpeak entries',
    );
    VerifiedArchiveManifestValidation.nonEmpty(
      license,
      name: 'license',
      label: 'The Piper model license',
    );
    VerifiedArchiveManifestValidation.nonNegative(
      downloadReserveBytes,
      name: 'downloadReserveBytes',
      label: 'The Piper download reserve',
    );

    return PiperModelManifest._(
      modelId: modelId,
      downloadUri: uri,
      revision: revision,
      archiveFilename: archiveFilename,
      archiveByteSize: archiveByteSize,
      archiveSha256: archiveSha256,
      expandedArchiveByteSize: expandedArchiveByteSize,
      extractedByteSize: extractedByteSize,
      extractedFileCount: extractedFileCount,
      bundleTreeSha256: bundleTreeSha256,
      archiveRoot: archiveRoot,
      modelFilename: modelFilename,
      tokensFilename: tokensFilename,
      espeakDataDirectory: espeakDataDirectory,
      license: license,
      downloadReserveBytes: downloadReserveBytes,
    );
  }

  const PiperModelManifest._({
    required this.modelId,
    required this.downloadUri,
    required this.revision,
    required this.archiveFilename,
    required this.archiveByteSize,
    required this.archiveSha256,
    required this.expandedArchiveByteSize,
    required this.extractedByteSize,
    required this.extractedFileCount,
    required this.bundleTreeSha256,
    required this.archiveRoot,
    required this.modelFilename,
    required this.tokensFilename,
    required this.espeakDataDirectory,
    required this.license,
    required this.downloadReserveBytes,
  });

  /// Stable upstream voice identifier.
  @override
  final String modelId;

  /// URL of the compressed, checksum-pinned voice archive.
  @override
  final Uri downloadUri;

  /// Exact upstream release or revision containing the archive.
  @override
  final String revision;

  /// Filename used for the archive download cache.
  @override
  final String archiveFilename;

  /// Exact expected compressed archive length.
  @override
  final int archiveByteSize;

  /// Lowercase SHA-256 digest of the compressed archive.
  @override
  final String archiveSha256;

  /// Exact tar byte length while the bzip2 archive is expanded for extraction.
  @override
  final int expandedArchiveByteSize;

  /// Exact sum of regular-file bytes in the extracted bundle.
  @override
  final int extractedByteSize;

  /// Exact number of regular files in the extracted bundle.
  @override
  final int extractedFileCount;

  /// Lowercase SHA-256 of the canonical extracted bundle tree.
  @override
  final String bundleTreeSha256;

  /// Single root directory expected inside the archive.
  @override
  final String archiveRoot;

  /// ONNX graph filename relative to [archiveRoot].
  final String modelFilename;

  /// Token-table filename relative to [archiveRoot].
  final String tokensFilename;

  /// eSpeak data directory relative to [archiveRoot].
  final String espeakDataDirectory;

  /// License identifier recorded for the selected voice.
  @override
  final String license;

  /// Free bytes retained beyond archive and extracted bundle storage.
  @override
  final int downloadReserveBytes;
}
