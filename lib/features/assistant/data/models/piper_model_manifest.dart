/// Immutable acquisition and integrity metadata for one Piper voice bundle.
final class PiperModelManifest {
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
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(
        downloadUrl,
        'downloadUrl',
        'The Piper URL must be an absolute HTTP or HTTPS URL.',
      );
    }
    _requireNonEmpty(modelId, 'modelId', 'The Piper model ID');
    _requireNonEmpty(revision, 'revision', 'The Piper revision');
    _requirePathComponent(
      archiveFilename,
      'archiveFilename',
      'The Piper archive filename',
    );
    _requirePositive(archiveByteSize, 'archiveByteSize', 'archive byte size');
    _requireSha256(archiveSha256, 'archiveSha256', 'archive SHA-256');
    _requirePositive(
      expandedArchiveByteSize,
      'expandedArchiveByteSize',
      'expanded archive byte size',
    );
    _requirePositive(
      extractedByteSize,
      'extractedByteSize',
      'extracted byte size',
    );
    _requirePositive(
      extractedFileCount,
      'extractedFileCount',
      'extracted file count',
    );
    _requireSha256(
      bundleTreeSha256,
      'bundleTreeSha256',
      'bundle tree SHA-256',
    );
    _requirePathComponent(
      archiveRoot,
      'archiveRoot',
      'The Piper archive root',
    );
    _requirePathComponent(
      modelFilename,
      'modelFilename',
      'The Piper model filename',
    );
    _requirePathComponent(
      tokensFilename,
      'tokensFilename',
      'The Piper tokens filename',
    );
    _requirePathComponent(
      espeakDataDirectory,
      'espeakDataDirectory',
      'The Piper eSpeak data directory',
    );
    _requireDistinctPathComponents(
      [archiveFilename, archiveRoot],
      'The Piper archive filename and extracted root',
    );
    _requireDistinctPathComponents(
      [modelFilename, tokensFilename, espeakDataDirectory],
      'The Piper model, tokens, and eSpeak entries',
    );
    _requireNonEmpty(license, 'license', 'The Piper model license');
    if (downloadReserveBytes < 0) {
      throw ArgumentError.value(
        downloadReserveBytes,
        'downloadReserveBytes',
        'The Piper download reserve must not be negative.',
      );
    }

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
  final String modelId;

  /// URL of the compressed, checksum-pinned voice archive.
  final Uri downloadUri;

  /// Exact upstream release or revision containing the archive.
  final String revision;

  /// Filename used for the archive download cache.
  final String archiveFilename;

  /// Exact expected compressed archive length.
  final int archiveByteSize;

  /// Lowercase SHA-256 digest of the compressed archive.
  final String archiveSha256;

  /// Exact tar byte length while the bzip2 archive is expanded for extraction.
  final int expandedArchiveByteSize;

  /// Exact sum of regular-file bytes in the extracted bundle.
  final int extractedByteSize;

  /// Exact number of regular files in the extracted bundle.
  final int extractedFileCount;

  /// Lowercase SHA-256 of the canonical extracted bundle tree.
  final String bundleTreeSha256;

  /// Single root directory expected inside the archive.
  final String archiveRoot;

  /// ONNX graph filename relative to [archiveRoot].
  final String modelFilename;

  /// Token-table filename relative to [archiveRoot].
  final String tokensFilename;

  /// eSpeak data directory relative to [archiveRoot].
  final String espeakDataDirectory;

  /// License identifier recorded for the selected voice.
  final String license;

  /// Free bytes retained beyond archive and extracted bundle storage.
  final int downloadReserveBytes;
}

void _requireNonEmpty(String value, String name, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$label must not be empty.');
  }
}

void _requirePathComponent(String value, String name, String label) {
  if (value.trim().isEmpty || value == '.' || value == '..' || value.contains('/') || value.contains(r'\')) {
    throw ArgumentError.value(
      value,
      name,
      '$label must be one non-empty path component.',
    );
  }
}

void _requirePositive(int value, String name, String label) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'The Piper $label must be positive.');
  }
}

void _requireSha256(String value, String name, String label) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'The Piper $label must contain 64 lowercase hexadecimal characters.',
    );
  }
}

void _requireDistinctPathComponents(List<String> values, String label) {
  if (values.map((value) => value.toLowerCase()).toSet().length != values.length) {
    throw ArgumentError('$label must use distinct cache paths.');
  }
}
