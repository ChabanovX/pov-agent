import 'package:pov_agent/features/assistant/data/models/verified_archive_model_manifest.dart';

/// Immutable acquisition and integrity metadata for one streaming ASR bundle.
final class AsrModelManifest implements VerifiedArchiveModelManifest {
  /// Creates and validates an injectable ASR bundle manifest.
  factory AsrModelManifest({
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
    required String license,
    required int downloadReserveBytes,
  }) {
    final uri = VerifiedArchiveManifestValidation.networkUri(
      downloadUrl,
      name: 'downloadUrl',
      label: 'The ASR URL',
    );
    VerifiedArchiveManifestValidation.nonEmpty(
      modelId,
      name: 'modelId',
      label: 'The ASR model ID',
    );
    VerifiedArchiveManifestValidation.nonEmpty(
      revision,
      name: 'revision',
      label: 'The ASR revision',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      archiveFilename,
      name: 'archiveFilename',
      label: 'The ASR archive filename',
    );
    VerifiedArchiveManifestValidation.positive(
      archiveByteSize,
      name: 'archiveByteSize',
      label: 'The ASR archive byte size',
    );
    VerifiedArchiveManifestValidation.sha256(
      archiveSha256,
      name: 'archiveSha256',
      label: 'The ASR archive SHA-256',
    );
    VerifiedArchiveManifestValidation.positive(
      expandedArchiveByteSize,
      name: 'expandedArchiveByteSize',
      label: 'The ASR expanded archive byte size',
    );
    VerifiedArchiveManifestValidation.positive(
      extractedByteSize,
      name: 'extractedByteSize',
      label: 'The ASR extracted byte size',
    );
    VerifiedArchiveManifestValidation.positive(
      extractedFileCount,
      name: 'extractedFileCount',
      label: 'The ASR extracted file count',
    );
    VerifiedArchiveManifestValidation.sha256(
      bundleTreeSha256,
      name: 'bundleTreeSha256',
      label: 'The ASR bundle tree SHA-256',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      archiveRoot,
      name: 'archiveRoot',
      label: 'The ASR archive root',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      modelFilename,
      name: 'modelFilename',
      label: 'The ASR model filename',
    );
    VerifiedArchiveManifestValidation.pathComponent(
      tokensFilename,
      name: 'tokensFilename',
      label: 'The ASR tokens filename',
    );
    VerifiedArchiveManifestValidation.distinctPathComponents(
      [archiveFilename, archiveRoot],
      label: 'The ASR archive filename and extracted root',
    );
    VerifiedArchiveManifestValidation.distinctPathComponents(
      [modelFilename, tokensFilename],
      label: 'The ASR model and tokens entries',
    );
    VerifiedArchiveManifestValidation.nonEmpty(
      license,
      name: 'license',
      label: 'The ASR model license',
    );
    VerifiedArchiveManifestValidation.nonNegative(
      downloadReserveBytes,
      name: 'downloadReserveBytes',
      label: 'The ASR download reserve',
    );

    return AsrModelManifest._(
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
      license: license,
      downloadReserveBytes: downloadReserveBytes,
    );
  }

  const AsrModelManifest._({
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
    required this.license,
    required this.downloadReserveBytes,
  });

  @override
  final String modelId;

  @override
  final Uri downloadUri;

  @override
  final String revision;

  @override
  final String archiveFilename;

  @override
  final int archiveByteSize;

  @override
  final String archiveSha256;

  @override
  final int expandedArchiveByteSize;

  @override
  final int extractedByteSize;

  @override
  final int extractedFileCount;

  @override
  final String bundleTreeSha256;

  @override
  final String archiveRoot;

  /// Streaming CTC ONNX graph filename relative to [archiveRoot].
  final String modelFilename;

  /// Token-table filename relative to [archiveRoot].
  final String tokensFilename;

  @override
  final String license;

  @override
  final int downloadReserveBytes;
}
