/// Latest native live-inference performance sample.
final class ObservationDiagnostics {
  /// Creates a timestamped inference diagnostics sample.
  const ObservationDiagnostics({
    required this.framesPerSecond,
    required this.inferenceTimeMs,
    required this.processingTimeMs,
    required this.frameNumber,
    required this.sampledAt,
  });

  /// The observed processing rate in frames per second.
  final double framesPerSecond;

  /// The model inference duration in milliseconds.
  final double inferenceTimeMs;

  /// The total frame processing duration in milliseconds.
  final double processingTimeMs;

  /// The source or observation frame number.
  final int frameNumber;

  /// The UTC time at which this sample was recorded.
  final DateTime sampledAt;
}
