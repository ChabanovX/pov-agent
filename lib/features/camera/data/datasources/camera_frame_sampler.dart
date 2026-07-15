import 'package:some_camera_with_llm/features/camera/data/dto/camera_frame_dto.dart';

typedef ElapsedTime = Duration Function();

/// Drops native frames until the configured monotonic sampling interval passes.
final class CameraFrameSampler {
  CameraFrameSampler({
    this.interval = const Duration(seconds: 1),
    ElapsedTime? elapsedTime,
  }) : _elapsedTime = elapsedTime ?? _createElapsedTime();

  final Duration interval;
  final ElapsedTime _elapsedTime;
  Duration? _lastSampleAt;

  CameraFrameDto? sample(CameraFrameDto Function() createFrame) {
    final now = _elapsedTime();
    final lastSampleAt = _lastSampleAt;
    if (lastSampleAt != null && now - lastSampleAt < interval) return null;

    _lastSampleAt = now;
    return createFrame();
  }

  void reset() {
    _lastSampleAt = null;
  }
}

ElapsedTime _createElapsedTime() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
