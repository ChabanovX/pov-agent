enum CameraLensDto { back, front, external }

final class CameraDeviceDto {
  const CameraDeviceDto({
    required this.id,
    required this.lens,
    required this.sensorOrientationDegrees,
  });

  final String id;
  final CameraLensDto lens;
  final int sensorOrientationDegrees;
}
