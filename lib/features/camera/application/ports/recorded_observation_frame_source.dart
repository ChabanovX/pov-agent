import 'package:some_camera_with_llm/features/camera/application/models/recorded_observation_frame.dart';

/// Publishes the recorded frame synchronized with each inference result.
abstract interface class RecordedObservationFrameSource {
  RecordedObservationFrame? get currentFrame;

  Stream<RecordedObservationFrame> get frames;
}
