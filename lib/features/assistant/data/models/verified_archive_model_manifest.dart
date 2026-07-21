/// Common acquisition and integrity facts for a verified tar.bz2 model bundle.
abstract interface class VerifiedArchiveModelManifest {
  /// Stable upstream model identifier.
  String get modelId;

  /// URL of the compressed, checksum-pinned model archive.
  Uri get downloadUri;

  /// Exact upstream release or revision containing the archive.
  String get revision;

  /// Filename used for the archive download cache.
  String get archiveFilename;

  /// Exact expected compressed archive length.
  int get archiveByteSize;

  /// Lowercase SHA-256 digest of the compressed archive.
  String get archiveSha256;

  /// Exact tar byte length while the bzip2 archive is expanded.
  int get expandedArchiveByteSize;

  /// Exact sum of regular-file bytes in the extracted bundle.
  int get extractedByteSize;

  /// Exact number of regular files in the extracted bundle.
  int get extractedFileCount;

  /// Lowercase SHA-256 of the canonical extracted bundle tree.
  String get bundleTreeSha256;

  /// Single root directory expected inside the archive.
  String get archiveRoot;

  /// License identifier recorded for the selected model.
  String get license;

  /// Free bytes retained beyond archive and extracted bundle storage.
  int get downloadReserveBytes;
}

/// Shared validation rules for injectable verified-archive manifests.
abstract final class VerifiedArchiveManifestValidation {
  /// Requires an absolute HTTP or HTTPS URL.
  static Uri networkUri(String value, {required String name, required String label}) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(
        value,
        name,
        '$label must be an absolute HTTP or HTTPS URL.',
      );
    }
    return uri;
  }

  /// Requires a non-empty text value.
  static void nonEmpty(String value, {required String name, required String label}) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, '$label must not be empty.');
    }
  }

  /// Requires one safe path component rather than a relative path.
  static void pathComponent(String value, {required String name, required String label}) {
    if (value.trim().isEmpty || value == '.' || value == '..' || value.contains('/') || value.contains(r'\')) {
      throw ArgumentError.value(
        value,
        name,
        '$label must be one non-empty path component.',
      );
    }
  }

  /// Requires a positive byte or file count.
  static void positive(int value, {required String name, required String label}) {
    if (value <= 0) {
      throw ArgumentError.value(value, name, '$label must be positive.');
    }
  }

  /// Requires a canonical lowercase SHA-256 digest.
  static void sha256(String value, {required String name, required String label}) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        '$label must contain 64 lowercase hexadecimal characters.',
      );
    }
  }

  /// Requires cache entries that remain distinct on case-insensitive volumes.
  static void distinctPathComponents(List<String> values, {required String label}) {
    if (values.map((value) => value.toLowerCase()).toSet().length != values.length) {
      throw ArgumentError('$label must use distinct cache paths.');
    }
  }

  /// Requires a non-negative retained-storage reserve.
  static void nonNegative(int value, {required String name, required String label}) {
    if (value < 0) {
      throw ArgumentError.value(value, name, '$label must not be negative.');
    }
  }
}
