import 'package:pov_agent/features/camera/application/models/recorded_observation_frame.dart';

/// A source of recorded frames synchronized with inference results.
abstract interface class RecordedObservationFrameSource {
  /// The latest synchronized frame, or `null` before the first result.
  RecordedObservationFrame? get currentFrame;

  /// Synchronized recorded frames published after successful inference.
  Stream<RecordedObservationFrame> get frames;
}
