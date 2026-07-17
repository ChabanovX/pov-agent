import 'dart:typed_data';

/// Dimensions and duration reported by a recorded video decoder.
final class RecordedVideoMetadata {
  const RecordedVideoMetadata({
    required this.frameWidth,
    required this.frameHeight,
    required this.duration,
  });

  final int frameWidth;
  final int frameHeight;
  final Duration duration;
}

/// One JPEG frame decoded from a recorded video at runtime.
final class RecordedVideoFrame {
  RecordedVideoFrame({
    required Uint8List encodedImage,
    required this.sourceFrameNumber,
    required this.presentationTime,
  }) : encodedImage = Uint8List.fromList(encodedImage).asUnmodifiableView();

  final Uint8List encodedImage;
  final int sourceFrameNumber;
  final Duration presentationTime;
}
