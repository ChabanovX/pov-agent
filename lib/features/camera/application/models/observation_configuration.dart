/// Stable Milestone 1 configuration shared by live and recorded inference.
final class ObservationConfiguration {
  const ObservationConfiguration({
    required this.modelPath,
    required this.cameraResolution,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.useGpu,
  });

  static const milestoneOne = ObservationConfiguration(
    modelPath: 'yolo26n',
    cameraResolution: '720p',
    confidenceThreshold: 0.4,
    iouThreshold: 0.7,
    useGpu: true,
  );

  final String modelPath;
  final String cameraResolution;
  final double confidenceThreshold;
  final double iouThreshold;
  final bool useGpu;
}
