import 'dart:typed_data';

import 'package:some_camera_with_llm/features/camera/data/dto/camera_device_dto.dart';

enum CameraFrameFormatDto { yuv420, bgra8888, nv21, jpeg, unknown }

final class CameraFramePlaneDto {
  CameraFramePlaneDto({
    required Uint8List bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
  }) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int? width;
  final int? height;
}

final class CameraFrameDto {
  CameraFrameDto({
    required this.width,
    required this.height,
    required this.format,
    required List<CameraFramePlaneDto> planes,
    required this.lens,
    required this.sensorOrientationDegrees,
    required this.capturedAt,
  }) : planes = List.unmodifiable(planes);

  final int width;
  final int height;
  final CameraFrameFormatDto format;
  final List<CameraFramePlaneDto> planes;
  final CameraLensDto lens;
  final int sensorOrientationDegrees;
  final DateTime capturedAt;
}
