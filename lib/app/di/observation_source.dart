/// Selects the image source used by the app-owned observation runtime.
enum ObservationSource {
  camera,
  recorded;

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
