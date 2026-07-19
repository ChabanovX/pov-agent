/// Reports insufficient free space for an artifact plus its retained reserve.
final class ModelInsufficientStorageException implements Exception {
  /// Creates a storage-capacity failure.
  const ModelInsufficientStorageException({
    required this.requiredBytes,
    required this.availableBytes,
  });

  /// Required free bytes before starting the transfer.
  final int requiredBytes;

  /// Free bytes reported by the model-cache volume.
  final int availableBytes;

  @override
  String toString() {
    return 'Model download requires $requiredBytes available bytes; '
        '$availableBytes bytes are available.';
  }
}

/// Reports bytes that do not match the pinned model manifest.
final class ModelIntegrityException implements Exception {
  /// Creates an artifact-integrity failure.
  const ModelIntegrityException({required this.reason});

  /// Diagnostic reason that the artifact was rejected.
  final String reason;

  @override
  String toString() => 'Model artifact failed verification: $reason';
}

/// Signals that a lifecycle transition invalidated the active preparation.
final class ModelPreparationCancelledException implements Exception {
  /// Creates the lifecycle cancellation signal.
  const ModelPreparationCancelledException();

  @override
  String toString() => 'Model preparation was cancelled.';
}
