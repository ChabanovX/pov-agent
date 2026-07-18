/// Compile-time flags that select application composition.
abstract final class CompilationConstants {
  /// Uses the bundled video stream instead of the device camera.
  static const bool usesRecordedVideo = bool.fromEnvironment(
    'USE_RECORDED_VIDEO',
  );
}
