/// Converts a validated positive second count into a [Duration].
///
/// Configuration parsers should reject non-finite or policy-specific values
/// before calling this helper. The defensive check here preserves the
/// invariant that sub-microsecond values cannot silently become zero.
Duration positiveSecondsDuration(double seconds, {required String name}) {
  final microseconds = (seconds * Duration.microsecondsPerSecond).round();
  if (microseconds <= 0) {
    throw ArgumentError.value(
      seconds,
      name,
      '$name must resolve to at least one microsecond.',
    );
  }
  return Duration(microseconds: microseconds);
}
