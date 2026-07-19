/// The immutable artifact metadata required to acquire the selected Qwen GGUF.
final class QwenModelManifest {
  /// Creates and validates an injectable artifact manifest.
  factory QwenModelManifest({
    required String modelId,
    required String downloadUrl,
    required String revision,
    required String filename,
    required int byteSize,
    required String sha256,
    required String license,
    required int downloadReserveBytes,
  }) {
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(
        downloadUrl,
        'downloadUrl',
        'The model URL must be an absolute HTTP or HTTPS URL.',
      );
    }
    if (modelId.trim().isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'The model ID must not be empty.');
    }
    if (revision.trim().isEmpty) {
      throw ArgumentError.value(revision, 'revision', 'The revision must not be empty.');
    }
    if (filename.trim().isEmpty || filename.contains('/') || filename.contains(r'\')) {
      throw ArgumentError.value(
        filename,
        'filename',
        'The model filename must be a single non-empty path component.',
      );
    }
    if (byteSize <= 0) {
      throw ArgumentError.value(byteSize, 'byteSize', 'The model byte size must be positive.');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(
        sha256,
        'sha256',
        'The model SHA-256 must contain 64 lowercase hexadecimal characters.',
      );
    }
    if (license.trim().isEmpty) {
      throw ArgumentError.value(license, 'license', 'The model license must not be empty.');
    }
    if (downloadReserveBytes < 0) {
      throw ArgumentError.value(
        downloadReserveBytes,
        'downloadReserveBytes',
        'The download reserve must not be negative.',
      );
    }

    return QwenModelManifest._(
      modelId: modelId,
      downloadUri: uri,
      revision: revision,
      filename: filename,
      byteSize: byteSize,
      sha256: sha256,
      license: license,
      downloadReserveBytes: downloadReserveBytes,
    );
  }

  const QwenModelManifest._({
    required this.modelId,
    required this.downloadUri,
    required this.revision,
    required this.filename,
    required this.byteSize,
    required this.sha256,
    required this.license,
    required this.downloadReserveBytes,
  });

  /// Stable upstream repository identifier.
  final String modelId;

  /// Immutable URL containing the pinned upstream revision.
  final Uri downloadUri;

  /// Exact upstream revision that owns the GGUF.
  final String revision;

  /// Filename used for both the download and verified cache.
  final String filename;

  /// Exact expected file length.
  final int byteSize;

  /// Lowercase SHA-256 digest of the expected bytes.
  final String sha256;

  /// SPDX identifier recorded for the model artifact.
  final String license;

  /// Free bytes retained after accounting for the model download.
  final int downloadReserveBytes;
}
