import 'dart:typed_data';

/// Dimensions and duration reported by a recorded video decoder.
final class RecordedVideoMetadata {
  /// Creates metadata for an opened recorded video.
  const RecordedVideoMetadata({
    required this.frameWidth,
    required this.frameHeight,
    required this.duration,
  });

  /// The decoded frame width in pixels.
  final int frameWidth;

  /// The decoded frame height in pixels.
  final int frameHeight;

  /// The source video's total playback duration.
  final Duration duration;
}

/// One JPEG frame decoded from a recorded video at runtime.
final class RecordedVideoFrame {
  /// Creates an immutable frame decoded from a recorded video.
  ///
  /// [encodedImage] is defensively copied into a read-only view.
  RecordedVideoFrame({
    required Uint8List encodedImage,
    required this.sourceFrameNumber,
    required this.presentationTime,
  }) : encodedImage = Uint8List.fromList(encodedImage).asUnmodifiableView();

  /// The read-only JPEG bytes for this frame.
  final Uint8List encodedImage;

  /// The frame number assigned by the platform decoder.
  final int sourceFrameNumber;

  /// The frame's presentation time in the source video.
  final Duration presentationTime;
}
