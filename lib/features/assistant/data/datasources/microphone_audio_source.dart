import 'dart:typed_data';

/// In-memory microphone capture consumed only inside the data layer.
///
/// Chunks are mono, little-endian signed PCM16. The contract deliberately has
/// no path parameter, so production recognition cannot persist user audio.
abstract interface class MicrophoneAudioSource {
  /// Starts one capture stream at [sampleRateHz].
  Future<Stream<Uint8List>> start({required int sampleRateHz});

  /// Stops active capture and settles after its stream closes.
  Future<void> stop();

  /// Permanently releases the native recorder.
  Future<void> close();
}

/// A non-programmer failure reported by microphone capture infrastructure.
final class MicrophoneCaptureException implements Exception {
  /// Creates a capture exception with a stable diagnostic [code].
  const MicrophoneCaptureException({
    required this.code,
    required this.message,
    this.cause,
  });

  /// Stable failure identifier used by the data-layer failure mapper.
  final String code;

  /// Diagnostic detail that is not presentation copy.
  final String message;

  /// Optional plugin error retained for diagnostics.
  final Object? cause;

  @override
  String toString() => 'MicrophoneCaptureException($code, $message)';
}
