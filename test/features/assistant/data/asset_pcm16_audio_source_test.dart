import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/datasources/asset_pcm16_audio_source.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';

void main() {
  test('paces one complete PCM16 fixture and leaves later captures silent', () async {
    final delays = <Completer<void>>[];
    final source = AssetPcm16AudioSource(
      assetBundle: _MemoryAssetBundle(Uint8List.fromList([0, 1, 2, 3, 4, 5])),
      assetPath: 'assets/audio/test.pcm',
      sampleRateHz: 10,
      delay: (_) {
        final delay = Completer<void>();
        delays.add(delay);
        return delay.future;
      },
    );

    final firstChunks = <Uint8List>[];
    final first = await source.start(sampleRateHz: 10);
    final firstSubscription = first.listen(firstChunks.add);
    await _flushEvents();
    expect(firstChunks, [
      Uint8List.fromList([0, 1]),
    ]);

    delays.removeAt(0).complete();
    await _flushEvents();
    expect(firstChunks, [
      Uint8List.fromList([0, 1]),
      Uint8List.fromList([2, 3]),
    ]);
    delays.removeAt(0).complete();
    await _flushEvents();
    expect(firstChunks.last, Uint8List.fromList([4, 5]));
    delays.removeAt(0).complete();
    await source.stop();
    await firstSubscription.cancel();

    final secondChunks = <Uint8List>[];
    final second = await source.start(sampleRateHz: 10);
    final secondSubscription = second.listen(secondChunks.add);
    await _flushEvents();
    expect(secondChunks, isEmpty);

    await source.stop();
    await secondSubscription.cancel();
    await source.close();
  });

  test('rejects sample-rate mismatch, concurrent start, and start after close', () async {
    final source = AssetPcm16AudioSource(
      assetBundle: _MemoryAssetBundle(Uint8List.fromList([0, 1])),
      assetPath: 'assets/audio/test.pcm',
      sampleRateHz: 16000,
      delay: (_) async {},
    );

    await expectLater(
      source.start(sampleRateHz: 8000),
      throwsA(
        isA<MicrophoneCaptureException>().having(
          (error) => error.code,
          'code',
          'recorded_audio_sample_rate_mismatch',
        ),
      ),
    );
    await source.start(sampleRateHz: 16000);
    await expectLater(
      source.start(sampleRateHz: 16000),
      throwsA(
        isA<MicrophoneCaptureException>().having(
          (error) => error.code,
          'code',
          'recorded_audio_source_busy',
        ),
      ),
    );
    await source.close();
    await expectLater(
      source.start(sampleRateHz: 16000),
      throwsA(
        isA<MicrophoneCaptureException>().having(
          (error) => error.code,
          'code',
          'recorded_audio_source_closed',
        ),
      ),
    );
  });

  test('maps missing and malformed fixtures to stable capture errors', () async {
    final missing = AssetPcm16AudioSource(
      assetBundle: _FailingAssetBundle(),
      assetPath: 'assets/audio/missing.pcm',
      sampleRateHz: 16000,
    );
    final malformed = AssetPcm16AudioSource(
      assetBundle: _MemoryAssetBundle(Uint8List.fromList([1])),
      assetPath: 'assets/audio/malformed.pcm',
      sampleRateHz: 16000,
    );

    await expectLater(
      missing.start(sampleRateHz: 16000),
      throwsA(
        isA<MicrophoneCaptureException>().having(
          (error) => error.code,
          'code',
          'recorded_audio_asset_load_failed',
        ),
      ),
    );
    await expectLater(
      malformed.start(sampleRateHz: 16000),
      throwsA(
        isA<MicrophoneCaptureException>().having(
          (error) => error.code,
          'code',
          'recorded_audio_invalid_pcm16',
        ),
      ),
    );
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async {
    final copy = Uint8List.fromList(bytes);
    return ByteData.sublistView(copy);
  }
}

final class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    return Future.error(StateError('Missing asset: $key'));
  }
}
