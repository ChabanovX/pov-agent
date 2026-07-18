/// A model and threshold configuration shared by observation runtimes.
final class ObservationConfiguration {
  /// Creates an observation configuration.
  const ObservationConfiguration({
    required this.modelPath,
    required this.cameraResolution,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.useGpu,
  });

  /// The production configuration fixed for Milestone 1 validation.
  static const milestoneOne = ObservationConfiguration(
    modelPath: 'yolo26n',
    cameraResolution: '720p',
    confidenceThreshold: 0.4,
    iouThreshold: 0.7,
    useGpu: true,
  );

  /// The model identifier resolved by the YOLO runtime.
  final String modelPath;

  /// The requested live-camera capture resolution.
  final String cameraResolution;

  /// The minimum confidence retained for a detection.
  final double confidenceThreshold;

  /// The intersection-over-union threshold used for suppression.
  final double iouThreshold;

  /// Whether inference should use graphics acceleration when available.
  final bool useGpu;
}
