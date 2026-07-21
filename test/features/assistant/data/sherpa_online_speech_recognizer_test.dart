import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/asr_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/sherpa_online_speech_recognizer.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/ffi/sherpa_online_recognition_worker.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  late List<String> lifecycle;
  late _FakeMicrophoneAudioSource audioSource;
  late _FakeOnlineRecognitionWorker worker;
  late SherpaOnlineSpeechRecognizer recognizer;

  setUp(() {
    lifecycle = <String>[];
    audioSource = _FakeMicrophoneAudioSource(lifecycle);
    worker = _FakeOnlineRecognitionWorker(lifecycle);
    recognizer = SherpaOnlineSpeechRecognizer(
      audioSource: audioSource,
      configuration: _configuration,
      workerFactory: () async => worker,
    );
  });

  test('forwards PCM and maps cumulative tagged worker events', () async {
    expect(await recognizer.loadModel(_bundle), isA<AppSuccess<void>>());
    final handle = _successHandle(await recognizer.start());
    final recognitionEvents = handle.events.take(2).toList();

    audioSource.add(Uint8List.fromList([0, 0, 1, 0]));
    await _waitFor(() => worker.audioChunks.isNotEmpty);
    worker
      ..emit(
        const AsrWorkerHypothesis(
          segmentId: 0,
          revision: 1,
          transcript: 'assistant what is here',
        ),
      )
      ..emit(
        const AsrWorkerEndpoint(
          segmentId: 0,
          revision: 2,
          transcript: 'assistant what is here',
          reason: SpeechRecognitionEndpointReason.trailingSilence,
        ),
      );

    expect(worker.audioChunks.single, orderedEquals([0, 0, 1, 0]));
    expect(
      await recognitionEvents,
      [
        isA<SpeechRecognitionHypothesis>()
            .having((event) => event.segmentId, 'segment', 0)
            .having((event) => event.revision, 'revision', 1)
            .having(
              (event) => event.transcript,
              'transcript',
              'assistant what is here',
            ),
        isA<SpeechRecognitionEndpoint>()
            .having((event) => event.segmentId, 'segment', 0)
            .having(
              (event) => event.reason,
              'reason',
              SpeechRecognitionEndpointReason.trailingSilence,
            ),
      ],
    );

    expect(await handle.resetForNextSegment(), isA<AppSuccess<void>>());
    expect(worker.resetCalls, 1);
    expect(await recognizer.start(), _failureWithCode('asr_stream_busy'));

    expect(await handle.stop(), isA<AppSuccess<void>>());
    expect(await handle.stop(), isA<AppSuccess<void>>());
    expect(audioSource.stopCalls, 1);
    expect(worker.stopCalls, 1);

    final secondHandle = _successHandle(await recognizer.start());
    expect(worker.startCalls, 2);
    await secondHandle.stop();
  });

  test('cleans native stream when microphone startup fails', () async {
    await recognizer.loadModel(_bundle);
    audioSource.onStart = () async {
      throw const MicrophoneCaptureException(
        code: 'microphone_capture_failed',
        message: 'Capture did not start.',
      );
    };

    expect(
      await recognizer.start(),
      _failureWithCode('microphone_capture_failed'),
    );
    expect(worker.startCalls, 1);
    expect(worker.stopCalls, 1);
    expect(audioSource.stopCalls, 1);

    audioSource.onStart = null;
    final handle = _successHandle(await recognizer.start());
    await handle.stop();
  });

  test('stop settles when a stale start result was never listened to', () async {
    await recognizer.loadModel(_bundle);
    final handle = _successHandle(await recognizer.start());

    expect(
      await handle.stop().timeout(const Duration(seconds: 1)),
      isA<AppSuccess<void>>(),
    );
    expect(audioSource.stopCalls, 1);
    expect(worker.stopCalls, 1);
  });

  test('unload waits for a pending start before stopping its handle', () async {
    await recognizer.loadModel(_bundle);
    final startGate = Completer<void>();
    audioSource.onStart = () => startGate.future;

    final pendingStart = recognizer.start();
    await _waitFor(() => worker.startCalls == 1);
    final pendingUnload = recognizer.unload();

    expect(await recognizer.start(), _failureWithCode('asr_recognizer_busy'));
    expect(lifecycle, isNot(contains('worker:unload')));

    startGate.complete();
    expect(await pendingStart, isA<AppSuccess<SpeechRecognitionHandle>>());
    expect(await pendingUnload, isA<AppSuccess<void>>());
    expect(
      lifecycle,
      containsAllInOrder([
        'audio:start',
        'audio:stop',
        'worker:stop',
        'worker:unload',
      ]),
    );
  });

  test('failed model replacement clears adapter readiness', () async {
    await recognizer.loadModel(_bundle);
    worker.onLoad = (_, _) async {
      throw const AsrWorkerException(
        code: 'asr_replacement_failed',
        message: 'Replacement failed after unloading the prior model.',
      );
    };

    expect(
      await recognizer.loadModel(_bundle),
      _failureWithCode('asr_replacement_failed'),
    );
    expect(await recognizer.start(), _failureWithCode('asr_model_not_loaded'));

    expect(await recognizer.unload(), isA<AppSuccess<void>>());
    expect(lifecycle.last, 'worker:unload');
  });

  test('publishes one normalized worker failure and stops capture', () async {
    await recognizer.loadModel(_bundle);
    final handle = _successHandle(await recognizer.start());
    final failureEvent = handle.events
        .where((event) => event is SpeechRecognitionFailure)
        .cast<SpeechRecognitionFailure>()
        .first;

    worker
      ..emit(
        const AsrWorkerFailure(
          segmentId: 0,
          revision: 1,
          failure: AsrWorkerException(
            code: 'asr_audio_backlog_overflow',
            message: 'Decoder backlog overflowed.',
          ),
        ),
      )
      ..emit(
        const AsrWorkerFailure(
          segmentId: 0,
          revision: 2,
          failure: AsrWorkerException(
            code: 'second_failure',
            message: 'Must be ignored.',
          ),
        ),
      );

    expect(
      await failureEvent,
      isA<SpeechRecognitionFailure>().having(
        (event) => event.failure.code,
        'code',
        'asr_audio_backlog_overflow',
      ),
    );
    await _waitFor(() => audioSource.stopCalls == 1 && worker.stopCalls == 1);

    final nextHandle = _successHandle(await recognizer.start());
    await nextHandle.stop();
  });

  test('failed stop retains the single-flight handle for retry', () async {
    await recognizer.loadModel(_bundle);
    final handle = _successHandle(await recognizer.start());
    var stopAttempts = 0;
    audioSource.onStop = () async {
      stopAttempts += 1;
      if (stopAttempts == 1) throw Exception('microphone stop failed');
    };

    expect(
      await handle.stop(),
      _failureWithCode('microphone_stop_failed'),
    );
    expect(await recognizer.start(), _failureWithCode('asr_stream_busy'));
    expect(worker.stopCalls, 1);

    expect(await handle.stop(), isA<AppSuccess<void>>());
    expect(stopAttempts, 2);
    expect(worker.stopCalls, 2);
  });

  test('terminal worker failure releases its handle and reloads on a new worker', () async {
    final replacement = _FakeOnlineRecognitionWorker(lifecycle);
    var workerFactoryCalls = 0;
    recognizer = SherpaOnlineSpeechRecognizer(
      audioSource: audioSource,
      configuration: _configuration,
      workerFactory: () async {
        workerFactoryCalls += 1;
        return workerFactoryCalls == 1 ? worker : replacement;
      },
    );
    await recognizer.loadModel(_bundle);
    final handle = _successHandle(await recognizer.start());
    final failureEvent = handle.events
        .where((event) => event is SpeechRecognitionFailure)
        .cast<SpeechRecognitionFailure>()
        .first;

    worker
      ..terminallyUnavailable = true
      ..emit(
        const AsrWorkerFailure(
          segmentId: 0,
          revision: 1,
          failure: AsrWorkerException(
            code: 'asr_worker_isolate_exited',
            message: 'The ASR isolate exited unexpectedly.',
          ),
        ),
      );

    expect(
      await failureEvent,
      isA<SpeechRecognitionFailure>().having(
        (event) => event.failure.code,
        'code',
        'asr_worker_isolate_exited',
      ),
    );
    expect(await handle.stop(), isA<AppSuccess<void>>());
    expect(worker.stopCalls, 0);

    final replacementHandle = _successHandle(await recognizer.start());
    expect(worker.closeCalls, 1);
    expect(workerFactoryCalls, 2);
    expect(replacement.startCalls, 1);
    expect(lifecycle.where((entry) => entry == 'worker:load'), hasLength(2));
    await replacementHandle.stop();
    await recognizer.close();
  });

  test('active handle recovers after its real worker isolate exits', () async {
    var workerFactoryCalls = 0;
    recognizer = SherpaOnlineSpeechRecognizer(
      audioSource: audioSource,
      configuration: _configuration,
      workerFactory: () async {
        workerFactoryCalls += 1;
        return SherpaOnlineRecognitionWorker.spawnForTesting(
          workerFactoryCalls == 1 ? _runExitingWorker : _runProtocolWorker,
        );
      },
    );
    await recognizer.loadModel(_bundle);
    final handle = _successHandle(await recognizer.start());
    final failureEvent = handle.events
        .where((event) => event is SpeechRecognitionFailure)
        .cast<SpeechRecognitionFailure>()
        .first;

    audioSource.add(Uint8List.fromList([0, 0]));

    expect(
      await failureEvent.timeout(const Duration(seconds: 2)),
      isA<SpeechRecognitionFailure>().having(
        (event) => event.failure.code,
        'code',
        anyOf('asr_worker_isolate_failed', 'asr_worker_isolate_exited'),
      ),
    );
    expect(
      await handle.stop().timeout(const Duration(seconds: 2)),
      isA<AppSuccess<void>>(),
    );

    final replacementHandle = _successHandle(
      await recognizer.start().timeout(const Duration(seconds: 2)),
    );
    expect(workerFactoryCalls, 2);
    await replacementHandle.stop();
    await recognizer.close();
  });

  test('unload stops capture before releasing model ownership', () async {
    await recognizer.loadModel(_bundle);
    _successHandle(await recognizer.start());

    expect(await recognizer.unload(), isA<AppSuccess<void>>());
    expect(
      lifecycle,
      containsAllInOrder([
        'audio:stop',
        'worker:stop',
        'worker:unload',
      ]),
    );
    expect(await recognizer.start(), _failureWithCode('asr_model_not_loaded'));
  });

  test('close releases microphone before persistent worker ports', () async {
    await recognizer.loadModel(_bundle);
    _successHandle(await recognizer.start());

    expect(await recognizer.close(), isA<AppSuccess<void>>());
    expect(await recognizer.close(), isA<AppSuccess<void>>());
    expect(
      lifecycle,
      containsAllInOrder([
        'audio:stop',
        'worker:stop',
        'audio:close',
        'worker:close',
      ]),
    );
    expect(audioSource.closeCalls, 1);
    expect(worker.closeCalls, 1);
  });
}

SpeechRecognitionHandle _successHandle(
  AppResult<SpeechRecognitionHandle> result,
) {
  return switch (result) {
    AppSuccess<SpeechRecognitionHandle>(:final value) => value,
    AppError<SpeechRecognitionHandle>(:final failure) => throw StateError(
      'Expected a recognition handle, got ${failure.code}.',
    ),
  };
}

Matcher _failureWithCode(String code) {
  return isA<AppError<Object?>>().having(
    (result) => result.failure,
    'failure',
    isA<AppFailure>().having((failure) => failure.code, 'code', code),
  );
}

final class _FakeMicrophoneAudioSource implements MicrophoneAudioSource {
  _FakeMicrophoneAudioSource(this.lifecycle);

  final List<String> lifecycle;
  StreamController<Uint8List>? _controller;
  Future<void> Function()? onStart;
  Future<void> Function()? onStop;
  int stopCalls = 0;
  int closeCalls = 0;

  @override
  Future<Stream<Uint8List>> start({required int sampleRateHz}) async {
    lifecycle.add('audio:start');
    await onStart?.call();
    _controller = StreamController<Uint8List>();
    return _controller!.stream;
  }

  void add(Uint8List bytes) => _controller!.add(bytes);

  @override
  Future<void> stop() async {
    lifecycle.add('audio:stop');
    stopCalls += 1;
    await onStop?.call();
    final controller = _controller;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<void> close() async {
    lifecycle.add('audio:close');
    closeCalls += 1;
  }
}

final class _FakeOnlineRecognitionWorker implements OnlineRecognitionWorker {
  _FakeOnlineRecognitionWorker(this.lifecycle);

  final List<String> lifecycle;
  final StreamController<AsrWorkerEvent> _events = StreamController<AsrWorkerEvent>.broadcast();
  final List<Uint8List> audioChunks = <Uint8List>[];
  Future<void> Function(
    VerifiedAsrModelBundle bundle,
    AsrRuntimeConfiguration configuration,
  )?
  onLoad;
  int startCalls = 0;
  int resetCalls = 0;
  int stopCalls = 0;
  int closeCalls = 0;
  bool terminallyUnavailable = false;

  @override
  Stream<AsrWorkerEvent> get events => _events.stream;

  @override
  bool get isTerminallyUnavailable => terminallyUnavailable;

  void emit(AsrWorkerEvent event) => _events.add(event);

  @override
  Future<void> load(
    VerifiedAsrModelBundle bundle,
    AsrRuntimeConfiguration configuration,
  ) async {
    lifecycle.add('worker:load');
    await onLoad?.call(bundle, configuration);
  }

  @override
  Future<void> start() async {
    lifecycle.add('worker:start');
    startCalls += 1;
  }

  @override
  Future<void> acceptAudio(Uint8List pcm16Bytes) async {
    audioChunks.add(Uint8List.fromList(pcm16Bytes));
  }

  @override
  Future<void> reset() async {
    lifecycle.add('worker:reset');
    resetCalls += 1;
  }

  @override
  Future<void> stop() async {
    lifecycle.add('worker:stop');
    stopCalls += 1;
  }

  @override
  Future<void> unload() async {
    lifecycle.add('worker:unload');
  }

  @override
  Future<void> close() async {
    lifecycle.add('worker:close');
    closeCalls += 1;
    await _events.close();
  }
}

Future<void> _runExitingWorker(SendPort events) async {
  final commands = ReceivePort();
  events.send(['ready', commands.sendPort]);
  await for (final Object? command in commands) {
    if (command case [final String name, final int requestId, ...]) {
      if (name == 'audio') {
        commands.close();
        throw StateError('Simulated terminal ASR isolate failure.');
      }
      events.send(['response', requestId, true, null]);
    }
  }
}

Future<void> _runProtocolWorker(SendPort events) async {
  final commands = ReceivePort();
  events.send(['ready', commands.sendPort]);
  await for (final Object? command in commands) {
    if (command case [_, final int requestId, ...]) {
      events.send(['response', requestId, true, null]);
    }
  }
}

const _configuration = AsrRuntimeConfiguration(
  provider: 'cpu',
  threadCount: 2,
  sampleRateHz: 16000,
  featureDimension: 80,
  decodingMethod: 'greedy_search',
  maxActivePaths: 4,
  rule1MinTrailingSilence: Duration(milliseconds: 2400),
  rule2MinTrailingSilence: Duration(milliseconds: 1200),
  maxUtteranceDuration: Duration(seconds: 15),
  debug: false,
  maxPendingAudioChunks: 8,
);

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

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition did not become true before timeout.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}
