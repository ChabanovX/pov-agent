import 'dart:typed_data';

import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';

/// Encodes generated mono PCM as a little-endian 16-bit WAV byte stream.
abstract final class Pcm16WavEncoder {
  static const _headerLength = 44;
  static const _bytesPerSample = 2;
  static const _maximumUint32 = 0xffffffff;

  /// Encodes [audio] entirely in memory.
  static Uint8List encode(GeneratedSpeechAudio audio) {
    final dataLength = audio.samples.length * _bytesPerSample;
    if (audio.sampleRateHz <= 0 ||
        audio.sampleRateHz * _bytesPerSample > _maximumUint32 ||
        dataLength == 0 ||
        dataLength > _maximumUint32 - 36) {
      throw ArgumentError.value(audio, 'audio', 'Invalid PCM dimensions.');
    }

    final bytes = Uint8List(_headerLength + dataLength);
    final data = ByteData.sublistView(bytes);
    _writeAscii(bytes, 0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    _writeAscii(bytes, 8, 'WAVE');
    _writeAscii(bytes, 12, 'fmt ');
    data
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, audio.sampleRateHz, Endian.little)
      ..setUint32(
        28,
        audio.sampleRateHz * _bytesPerSample,
        Endian.little,
      )
      ..setUint16(32, _bytesPerSample, Endian.little)
      ..setUint16(34, 16, Endian.little);
    _writeAscii(bytes, 36, 'data');
    data.setUint32(40, dataLength, Endian.little);

    for (var index = 0; index < audio.samples.length; index += 1) {
      data.setInt16(
        _headerLength + index * _bytesPerSample,
        _quantize(audio.samples[index]),
        Endian.little,
      );
    }
    return bytes;
  }

  static int _quantize(double sample) {
    if (!sample.isFinite) {
      throw ArgumentError.value(sample, 'sample', 'PCM samples must be finite.');
    }
    final clipped = sample.clamp(-1.0, 1.0);
    // Preserve the full negative PCM16 endpoint while keeping +1 representable.
    return (clipped * (clipped.isNegative ? 32768 : 32767)).round();
  }

  static void _writeAscii(Uint8List bytes, int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }
}
