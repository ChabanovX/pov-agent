/// The image source used by the app-owned observation runtime.
enum ObservationSource {
  /// Live frames from device camera hardware.
  camera,

  /// Frames decoded from the bundled recorded video.
  recorded;

  /// The source represented by [value], ignoring case and surrounding space.
  ///
  /// Throws an [ArgumentError] when [value] is not a supported source name.
  static ObservationSource parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'camera' => ObservationSource.camera,
      'recorded' => ObservationSource.recorded,
      _ => throw ArgumentError.value(
        value,
        'OBSERVATION_SOURCE',
        'Expected "camera" or "recorded".',
      ),
    };
  }
}
