import 'package:some_camera_with_llm/features/camera/application/models/recorded_video_frame.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// Pull-based runtime decoder for a looping recorded video.
abstract interface class RecordedVideoFrameSource {
  Future<AppResult<RecordedVideoMetadata>> open();

  Future<AppResult<RecordedVideoFrame>> nextFrame();

  Future<AppResult<void>> close();
}
