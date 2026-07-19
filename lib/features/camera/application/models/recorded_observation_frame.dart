import 'dart:typed_data';

import 'package:pov_agent/features/camera/domain/entities/detection.dart';

/// One recorded frame and the model detections synchronized with that image.
final class RecordedObservationFrame {
  /// Creates an immutable recorded observation frame.
  ///
  /// Both [encodedImage] and [detections] are defensively copied.
  RecordedObservationFrame({
    required Uint8List encodedImage,
    required List<Detection> detections,
    required this.frameNumber,
    required this.frameWidth,
    required this.frameHeight,
  }) : encodedImage = Uint8List.fromList(encodedImage).asUnmodifiableView(),
       detections = List.unmodifiable(detections);

  /// The read-only encoded image bytes rendered for this frame.
  final Uint8List encodedImage;

  /// The immutable detections synchronized with [encodedImage].
  final List<Detection> detections;

  /// The sequential observation number assigned after inference.
  final int frameNumber;

  /// The decoded frame width in pixels.
  final int frameWidth;

  /// The decoded frame height in pixels.
  final int frameHeight;

  /// The decoded frame's width-to-height ratio.
  double get aspectRatio => frameWidth / frameHeight;
}
