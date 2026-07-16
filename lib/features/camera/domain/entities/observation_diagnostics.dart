/// Latest native live-inference performance sample.
final class ObservationDiagnostics {
  const ObservationDiagnostics({
    required this.framesPerSecond,
    required this.inferenceTimeMs,
    required this.processingTimeMs,
    required this.frameNumber,
    required this.sampledAt,
  });

  final double framesPerSecond;
  final double inferenceTimeMs;
  final double processingTimeMs;
  final int frameNumber;
  final DateTime sampledAt;
}
