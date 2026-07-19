import 'package:pov_agent/features/camera/application/models/recorded_video_frame.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Pull-based runtime decoder for a looping recorded video.
abstract interface class RecordedVideoFrameSource {
  /// Opens the decoder and returns validated source metadata.
  Future<AppResult<RecordedVideoMetadata>> open();

  /// Decodes the next frame, looping according to the source implementation.
  Future<AppResult<RecordedVideoFrame>> nextFrame();

  /// Releases the decoder and its platform resources.
  Future<AppResult<void>> close();
}
