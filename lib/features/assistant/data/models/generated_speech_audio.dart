import 'dart:collection';
import 'dart:typed_data';

/// A mono floating-point PCM utterance produced by the local speech runtime.
///
/// Construction snapshots [samples], so the native synthesis buffer can be
/// released before playback finishes without changing the queued audio.
final class GeneratedSpeechAudio {
  /// Creates an owned PCM snapshot at [sampleRateHz].
  GeneratedSpeechAudio({
    required List<double> samples,
    required this.sampleRateHz,
  }) : samples = UnmodifiableListView(Float32List.fromList(samples));

  /// Normalized mono samples, conventionally in the `-1.0 ... 1.0` range.
  final List<double> samples;

  /// Number of PCM samples per second.
  final int sampleRateHz;

  /// Nominal duration derived from the sample count.
  Duration get duration => Duration(
    microseconds: samples.length * Duration.microsecondsPerSecond ~/ sampleRateHz,
  );
}
