import 'dart:typed_data';

import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';

/// Cross-platform pixel formats produced by the camera frame stream.
enum CameraFrameFormat { yuv420, bgra8888, nv21, jpeg, unknown }

/// Owns one immutable plane of raw camera pixels.
final class CameraFramePlane {
  CameraFramePlane({
    required Uint8List bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int? width;
  final int? height;
}

/// A sampled, platform-independent raw camera frame.
final class CameraFrame {
  CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required List<CameraFramePlane> planes,
    required this.lens,
    required this.sensorOrientationDegrees,
    required DateTime capturedAt,
  }) : planes = List.unmodifiable(planes),
       capturedAt = capturedAt.toUtc();

  final int width;
  final int height;
  final CameraFrameFormat format;
  final List<CameraFramePlane> planes;
  final CameraLens lens;

  /// Clockwise sensor rotation relative to the device's natural orientation.
  final int sensorOrientationDegrees;

  final DateTime capturedAt;
}
