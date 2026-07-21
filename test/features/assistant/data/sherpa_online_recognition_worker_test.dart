import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/asr_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/data/ffi/sherpa_online_recognition_worker.dart';

void main() {
  test('builds the selected NeMo streaming CTC native configuration', () {
    final configuration = _configuration();
    final native = buildSherpaOnlineRecognizerConfiguration(
      _bundle,
      configuration,
    );

    expect(native.feat.sampleRate, 16000);
    expect(native.feat.featureDim, 80);
    expect(native.model.nemoCtc.model, _bundle.modelFilePath);
    expect(native.model.tokens, _bundle.tokensFilePath);
    expect(native.model.numThreads, 2);
    expect(native.model.provider, 'cpu');
    expect(native.model.debug, isFalse);
    expect(native.decodingMethod, 'greedy_search');
    expect(native.maxActivePaths, 4);
    expect(native.rule1MinTrailingSilence, 2.4);
    expect(native.rule2MinTrailingSilence, 1.2);
    expect(native.rule3MinUtteranceLength, 15);
  });

  group('Pcm16LittleEndianDecoder', () {
    test('normalizes signed little-endian PCM16 samples', () {
      final decoder = Pcm16LittleEndianDecoder();

      final samples = decoder.decode(
        Uint8List.fromList([
          0x00,
          0x00,
          0xff,
          0x7f,
          0x00,
          0x80,
          0xff,
          0xff,
        ]),
      );

      expect(samples[0], 0);
      expect(samples[1], closeTo(32767 / 32768, 0.000001));
      expect(samples[2], -1);
      expect(samples[3], closeTo(-1 / 32768, 0.000001));
      decoder.finish();
    });

    test('carries a split sample across plugin chunk boundaries', () {
      final decoder = Pcm16LittleEndianDecoder();

      expect(decoder.decode(Uint8List.fromList([0x00])), isEmpty);
      expect(decoder.decode(Uint8List.fromList([0x80])), orderedEquals([-1]));
      decoder.finish();
    });

    test('rejects a genuinely truncated final sample and resets it', () {
      final decoder = Pcm16LittleEndianDecoder()..decode(Uint8List.fromList([0x01]));

      expect(
        decoder.finish,
        throwsA(
          isA<AsrWorkerException>().having(
            (error) => error.code,
            'code',
            'asr_pcm_truncated_sample',
          ),
        ),
      );

      Pcm16LittleEndianDecoder()
        ..decode(Uint8List.fromList([0x01]))
        ..reset()
        ..finish();
    });
  });

  test('shutdown retries native free before foreground disposal', () async {
    final nativeFailure = Exception('native free failed');
    var nativeCloseCalls = 0;
    var disposeCalls = 0;
    final shutdown = AsrWorkerShutdownCoordinator(
      closeNative: () async {
        nativeCloseCalls += 1;
        if (nativeCloseCalls == 1) throw nativeFailure;
      },
      dispose: () async {
        disposeCalls += 1;
      },
    );

    await expectLater(shutdown.close(), throwsA(same(nativeFailure)));
    expect(shutdown.isClosing, isFalse);
    expect(shutdown.isClosed, isFalse);
    expect(disposeCalls, 0);

    await shutdown.close();
    await shutdown.close();
    expect(shutdown.isClosed, isTrue);
    expect(nativeCloseCalls, 2);
    expect(disposeCalls, 1);
  });

  test('persistent protocol preserves tags across reset and close', () async {
    final worker = await SherpaOnlineRecognitionWorker.spawnForTesting(
      _runDeterministicWorker,
    );
    await worker.load(_bundle, _configuration());
    await worker.start();

    final firstEvents = worker.events.take(2).toList();
    await worker.acceptAudio(Uint8List.fromList([0, 0]));
    expect(
      await firstEvents,
      [
        isA<AsrWorkerHypothesis>()
            .having((event) => event.segmentId, 'segment', 0)
            .having((event) => event.revision, 'revision', 1)
            .having((event) => event.transcript, 'transcript', 'assistant'),
        isA<AsrWorkerEndpoint>()
            .having((event) => event.segmentId, 'segment', 0)
            .having((event) => event.revision, 'revision', 2)
            .having(
              (event) => event.reason,
              'reason',
              SpeechRecognitionEndpointReason.trailingSilence,
            ),
      ],
    );

    await worker.reset();
    final secondEvents = worker.events.take(2).toList();
    await worker.acceptAudio(Uint8List.fromList([0, 0]));
    expect(
      await secondEvents,
      [
        isA<AsrWorkerHypothesis>().having(
          (event) => event.segmentId,
          'segment',
          1,
        ),
        isA<AsrWorkerEndpoint>().having(
          (event) => event.segmentId,
          'segment',
          1,
        ),
      ],
    );

    await worker.stop();
    await worker.unload();
    await worker.close();
    await worker.close();
  });

  test('fails deterministically before isolate audio backlog grows', () async {
    final worker = await SherpaOnlineRecognitionWorker.spawnForTesting(
      _runSlowWorker,
    );
    await worker.load(_bundle, _configuration(maxPendingAudioChunks: 1));
    await worker.start();
    final failureEvent = worker.events.where((event) => event is AsrWorkerFailure).cast<AsrWorkerFailure>().first;

    final firstAudio = worker.acceptAudio(Uint8List.fromList([0, 0]));
    await Future<void>.delayed(Duration.zero);
    await worker.acceptAudio(Uint8List.fromList([1, 0]));

    expect(
      await failureEvent,
      isA<AsrWorkerFailure>().having(
        (event) => event.failure.code,
        'code',
        'asr_audio_backlog_overflow',
      ),
    );
    await firstAudio;
    await worker.stop();
    await worker.close();
  });
}

Future<void> _runDeterministicWorker(SendPort events) async {
  final commands = ReceivePort();
  events.send(['ready', commands.sendPort]);
  var segmentId = 0;
  var revision = 0;
  await for (final Object? command in commands) {
    if (command case [final String name, final int requestId, ...]) {
      if (name == 'start') {
        segmentId = 0;
        revision = 0;
      } else if (name == 'reset') {
        segmentId += 1;
      } else if (name == 'audio') {
        revision += 1;
        events.send([
          'hypothesis',
          segmentId,
          revision,
          'assistant',
        ]);
        revision += 1;
        events.send([
          'endpoint',
          segmentId,
          revision,
          'assistant',
          SpeechRecognitionEndpointReason.trailingSilence.name,
        ]);
      }
      events.send(['response', requestId, true, null]);
    }
  }
}

Future<void> _runSlowWorker(SendPort events) async {
  final commands = ReceivePort();
  events.send(['ready', commands.sendPort]);
  await for (final Object? command in commands) {
    if (command case [final String name, final int requestId, ...]) {
      if (name == 'audio') {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      events.send(['response', requestId, true, null]);
    }
  }
}

const _bundle = VerifiedAsrModelBundle(
  modelId: 'asr-test',
  revision: 'test-revision',
  bundleDirectoryPath: '/verified/asr',
  modelFilePath: '/verified/asr/model.int8.onnx',
  tokensFilePath: '/verified/asr/tokens.txt',
  extractedByteSize: 10,
  extractedFileCount: 2,
  bundleTreeSha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);

AsrRuntimeConfiguration _configuration({int maxPendingAudioChunks = 8}) {
  return AsrRuntimeConfiguration(
    provider: 'cpu',
    threadCount: 2,
    sampleRateHz: 16000,
    featureDimension: 80,
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
    rule1MinTrailingSilence: const Duration(milliseconds: 2400),
    rule2MinTrailingSilence: const Duration(milliseconds: 1200),
    maxUtteranceDuration: const Duration(seconds: 15),
    debug: false,
    maxPendingAudioChunks: maxPendingAudioChunks,
  );
}
