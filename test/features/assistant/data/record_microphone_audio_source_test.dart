import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/datasources/record_microphone_audio_source.dart';
import 'package:record/record.dart';

void main() {
  group('RecordMicrophoneAudioSource', () {
    test('forwards only in-memory mono PCM16 chunks', () async {
      final backend = _FakeMicrophoneRecorderBackend();
      final source = RecordMicrophoneAudioSource(backend: backend);

      final stream = await source.start(sampleRateHz: 16000);
      final received = <Uint8List>[];
      final subscription = stream.listen(received.add);
      backend.audio.add(Uint8List.fromList([0, 1, 2, 3]));
      await _flushEventQueue();

      expect(backend.sampleRates, [16000]);
      expect(backend.streamBufferBytes, [3200]);
      expect(received.single, orderedEquals([0, 1, 2, 3]));

      await source.stop();
      await subscription.cancel();
      expect(backend.stopCalls, 1);
      await source.close();
      expect(backend.closeCalls, 1);
    });

    test('rejects unsupported PCM16 before capture starts', () async {
      final backend = _FakeMicrophoneRecorderBackend()..supported = false;
      final source = RecordMicrophoneAudioSource(backend: backend);

      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(
          isA<MicrophoneCaptureException>().having(
            (error) => error.code,
            'code',
            'microphone_pcm16_unsupported',
          ),
        ),
      );
      expect(backend.startCalls, 0);
    });

    test('reserves the capture slot across an in-flight native start', () async {
      final startGate = Completer<void>();
      final backend = _FakeMicrophoneRecorderBackend()..onStart = () => startGate.future;
      final source = RecordMicrophoneAudioSource(backend: backend);

      final firstStart = source.start(sampleRateHz: 16000);
      await _flushEventQueue();
      expect(backend.startCalls, 1);

      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(
          isA<MicrophoneCaptureException>().having(
            (error) => error.code,
            'code',
            'microphone_capture_busy',
          ),
        ),
      );
      expect(backend.startCalls, 1);

      startGate.complete();
      await firstStart;
      await source.stop();
    });

    test('stop and close settle the same in-flight start before teardown', () async {
      final startGate = Completer<void>();
      final backend = _FakeMicrophoneRecorderBackend()..onStart = () => startGate.future;
      final source = RecordMicrophoneAudioSource(backend: backend);

      final start = source.start(sampleRateHz: 16000);
      await _flushEventQueue();
      final stop = source.stop();
      final close = source.close();
      final joinedClose = source.close();
      await _flushEventQueue();

      expect(identical(close, joinedClose), isTrue);
      expect(backend.stopCalls, 0);
      expect(backend.closeCalls, 0);

      startGate.complete();
      await start;
      await Future.wait([stop, close, joinedClose]);

      expect(backend.startCalls, 1);
      expect(backend.stopCalls, 1);
      expect(backend.closeCalls, 1);
      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(
          isA<MicrophoneCaptureException>().having(
            (error) => error.code,
            'code',
            'microphone_capture_closed',
          ),
        ),
      );
    });

    test('keeps stop single-flight and permits a later capture', () async {
      final backend = _FakeMicrophoneRecorderBackend();
      final source = RecordMicrophoneAudioSource(backend: backend);
      await source.start(sampleRateHz: 16000);

      final stopGate = Completer<void>();
      backend.onStop = () => stopGate.future;
      final firstStop = source.stop();
      final joinedStop = source.stop();

      expect(identical(firstStop, joinedStop), isTrue);
      stopGate.complete();
      await firstStop;

      backend.onStop = null;
      await source.start(sampleRateHz: 16000);
      expect(backend.startCalls, 2);
      await source.stop();
    });

    test('retains capture ownership after failed stop for retry', () async {
      final backend = _FakeMicrophoneRecorderBackend();
      final source = RecordMicrophoneAudioSource(backend: backend);
      await source.start(sampleRateHz: 16000);
      var stopAttempts = 0;
      backend.onStop = () async {
        stopAttempts += 1;
        if (stopAttempts == 1) throw Exception('native stop failed');
      };

      await expectLater(source.stop(), throwsException);
      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(
          isA<MicrophoneCaptureException>().having(
            (error) => error.code,
            'code',
            'microphone_capture_busy',
          ),
        ),
      );

      await source.stop();
      expect(stopAttempts, 2);
    });

    test('close joins an already in-flight retryable stop', () async {
      final backend = _FakeMicrophoneRecorderBackend();
      final source = RecordMicrophoneAudioSource(backend: backend);
      await source.start(sampleRateHz: 16000);
      final stopGate = Completer<void>();
      backend.onStop = () => stopGate.future;

      final stop = source.stop();
      final close = source.close();
      await _flushEventQueue();

      expect(backend.stopCalls, 1);
      expect(backend.closeCalls, 0);

      stopGate.complete();
      await Future.wait([stop, close]);
      expect(backend.stopCalls, 1);
      expect(backend.closeCalls, 1);
    });

    test('failed close remains terminal and retries native release', () async {
      final closeFailure = Exception('native close failed');
      var closeAttempts = 0;
      final backend = _FakeMicrophoneRecorderBackend()
        ..onClose = () async {
          closeAttempts += 1;
          if (closeAttempts == 1) throw closeFailure;
        };
      final source = RecordMicrophoneAudioSource(backend: backend);

      await expectLater(source.close(), throwsA(same(closeFailure)));
      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(
          isA<MicrophoneCaptureException>().having(
            (error) => error.code,
            'code',
            'microphone_capture_closed',
          ),
        ),
      );

      await source.close();
      expect(backend.closeCalls, 2);
    });

    test('rolls back native capture when stream startup throws', () async {
      final startFailure = Exception('stream startup failed');
      final backend = _FakeMicrophoneRecorderBackend()..onStart = () => Future.error(startFailure);
      final source = RecordMicrophoneAudioSource(backend: backend);

      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(same(startFailure)),
      );
      expect(backend.stopCalls, 1);
    });

    test('retains possible native ownership when startup rollback fails', () async {
      final startFailure = Exception('stream startup failed');
      final cleanupFailure = Exception('startup rollback failed');
      var stopAttempts = 0;
      final backend = _FakeMicrophoneRecorderBackend()
        ..onStart = () async {
          throw startFailure;
        }
        ..onStop = () async {
          stopAttempts += 1;
          if (stopAttempts == 1) throw cleanupFailure;
        };
      final source = RecordMicrophoneAudioSource(backend: backend);

      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(same(cleanupFailure)),
      );
      await expectLater(
        source.start(sampleRateHz: 16000),
        throwsA(
          isA<MicrophoneCaptureException>().having(
            (error) => error.code,
            'code',
            'microphone_capture_busy',
          ),
        ),
      );

      await source.stop();
      expect(stopAttempts, 2);

      backend.onStart = null;
      await source.start(sampleRateHz: 16000);
      await source.stop();
      expect(backend.startCalls, 2);
    });
  });

  group('RecordMicrophoneRecorderBackend', () {
    late RecordPlatform originalPlatform;
    late _FakeRecordPlatform platform;

    setUp(() {
      originalPlatform = RecordPlatform.instance;
      platform = _FakeRecordPlatform();
      RecordPlatform.instance = platform;
    });

    tearDown(() {
      RecordPlatform.instance = originalPlatform;
    });

    test('uses record startStream with the exact ASR PCM contract', () async {
      final backend = RecordMicrophoneRecorderBackend();

      expect(await backend.supportsPcm16Stream(), isTrue);
      final stream = await backend.startPcm16Stream(
        sampleRateHz: 16000,
        streamBufferBytes: 3200,
      );
      final subscription = stream.listen((_) {});

      final config = platform.startedConfig;
      expect(config, isNotNull);
      expect(config!.encoder, AudioEncoder.pcm16bits);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.streamBufferSize, 3200);
      expect(config.autoGain, isTrue);
      expect(config.echoCancel, isTrue);
      expect(config.noiseSuppress, isTrue);
      expect(platform.fileStartCalls, 0);

      await backend.stop();
      await subscription.cancel();
      await backend.close();
      expect(platform.disposeCalls, 1);
    });
  });
}

final class _FakeMicrophoneRecorderBackend implements MicrophoneRecorderBackend {
  bool supported = true;
  int startCalls = 0;
  int stopCalls = 0;
  int closeCalls = 0;
  final sampleRates = <int>[];
  final streamBufferBytes = <int>[];
  StreamController<Uint8List> audio = StreamController<Uint8List>.broadcast();
  Future<void> Function()? onStop;
  Future<void> Function()? onStart;
  Future<void> Function()? onClose;

  @override
  Future<bool> supportsPcm16Stream() async => supported;

  @override
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRateHz,
    required int streamBufferBytes,
  }) async {
    startCalls += 1;
    await onStart?.call();
    sampleRates.add(sampleRateHz);
    this.streamBufferBytes.add(streamBufferBytes);
    if (audio.isClosed) audio = StreamController<Uint8List>.broadcast();
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    await onStop?.call();
    if (!audio.isClosed) await audio.close();
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await onClose?.call();
  }
}

final class _FakeRecordPlatform extends RecordPlatform {
  RecordConfig? startedConfig;
  int fileStartCalls = 0;
  int disposeCalls = 0;
  final audio = StreamController<Uint8List>();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async {
    return encoder == AudioEncoder.pcm16bits;
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    startedConfig = config;
    return audio.stream;
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    fileStartCalls += 1;
  }

  @override
  Future<String?> stop(String recorderId) async {
    if (!audio.isClosed) await audio.close();
    return null;
  }

  @override
  Future<void> dispose(String recorderId) async {
    disposeCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flushEventQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
