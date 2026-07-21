/// Persists only the verified model-pack fingerprint.
abstract interface class ModelPackReceiptStore {
  /// Reads the last fully verified fingerprint, or `null` when none exists.
  Future<String?> read();

  /// Atomically records [fingerprint] after every required model verifies.
  Future<void> write(String fingerprint);

  /// Removes a stale receipt without deleting any model artifact.
  Future<void> clear();
}
