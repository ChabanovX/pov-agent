import 'dart:typed_data';

import 'package:some_camera_with_llm/features/camera/domain/entities/detection.dart';

/// One recorded frame and the model detections synchronized with that image.
final class RecordedObservationFrame {
  RecordedObservationFrame({
    required Uint8List encodedImage,
    required List<Detection> detections,
    required this.frameNumber,
    required this.frameWidth,
    required this.frameHeight,
  }) : encodedImage = Uint8List.fromList(encodedImage).asUnmodifiableView(),
       detections = List.unmodifiable(detections);

  final Uint8List encodedImage;
  final List<Detection> detections;
  final int frameNumber;
  final int frameWidth;
  final int frameHeight;

  double get aspectRatio => frameWidth / frameHeight;
}
