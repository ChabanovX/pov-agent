import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/services/wake_phrase_detector.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_voice_input_session.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

const _bundle = VerifiedAsrModelBundle(
  modelId: 'test-asr',
  revision: 'test-revision',
  bundleDirectoryPath: '/tmp/test-asr',
  modelFilePath: '/tmp/test-asr/model.int8.onnx',
  tokensFilePath: '/tmp/test-asr/tokens.txt',
  extractedByteSize: 2,
  extractedFileCount: 2,
  bundleTreeSha256: 'test-tree',
);

void main() {
  test('prepares, requests permission, loads, and arms exactly once', () async {
    final fixture = _VoiceFixture();

    expect(await fixture.session.watch(), isA<AppSuccess<void>>());
    expect(await fixture.session.watch(), isA<AppSuccess<void>>());

    expect(fixture.store.prepareCalls, 1);
    expect(fixture.permission.requestCalls, 1);
    expect(fixture.recognizer.loadCalls, 1);
    expect(fixture.recognizer.startCalls, 1);
    expect(fixture.updates.whereType<ObserverVoiceWatching>(), hasLength(1));
    await fixture.close();
  });

  testWidgets(
    'closes an armed session without queued recognition events',
    (tester) async {
      final fixture = _VoiceFixture();
      await fixture.session.watch();
      await tester.pump();

      await tester.runAsync(fixture.close);

      expect(fixture.handle.stopCalls, 1);
    },
  );

  test('matches a cumulative wake once and completes one question', () async {
    final fixture = _VoiceFixture();
    await fixture.session.watch();

    fixture.handle
      ..hypothesis(segmentId: 0, revision: 1, transcript: 'assi')
      ..hypothesis(
        segmentId: 0,
        revision: 2,
        transcript: 'Assistant, what',
      );
    await _flushEvents();

    expect(
      fixture.updates.whereType<ObserverVoiceWakeDetected>(),
      hasLength(1),
    );
    expect(
      fixture.updates.whereType<ObserverVoiceListeningStarted>().single.transcript,
      'what',
    );
    expect(fixture.handle.resetCalls, 1);

    fixture.handle
      ..hypothesis(
        segmentId: 1,
        revision: 3,
        transcript: 'can you see',
      )
      ..endpoint(
        segmentId: 1,
        revision: 4,
        transcript: 'can you see',
      )
      ..endpoint(
        segmentId: 1,
        revision: 5,
        transcript: 'can you see',
      );
    await _flushEvents();

    final questions = fixture.updates.whereType<ObserverVoiceQuestionCompleted>().toList();
    expect(questions, hasLength(1));
    expect(questions.single.question, 'what can you see');
    expect(fixture.handle.stopCalls, 1);
    expect(fixture.session.isWatching, isFalse);
    await fixture.close();
  });

  test('rearmed watcher reports stream failure outside the completed turn', () async {
    final fixture = _VoiceFixture(
      permissionResults: [
        const AppSuccess<void>(null),
        const AppSuccess<void>(null),
      ],
    );
    await fixture.session.watch();
    fixture.handle.endpoint(
      segmentId: 0,
      revision: 1,
      transcript: 'Assistant what is here',
    );
    await _flushEvents();

    final replacement = _FakeSpeechRecognitionHandle();
    fixture.recognizer.handles.add(replacement);
    await fixture.session.watch();
    replacement.failure(
      segmentId: 0,
      revision: 1,
      failure: const DeviceUnavailableFailure(code: 'asr_stream_failed'),
    );
    await _flushEvents();

    final failures = fixture.updates.whereType<ObserverVoiceInputFailed>().toList();
    expect(failures, hasLength(1));
    expect(failures.single.turnId, isNull);
    expect(failures.single.failure.code, 'asr_stream_failed');
    await fixture.close();
  });

  test('wake-only endpoint becomes a recoverable empty-question failure', () async {
    final fixture = _VoiceFixture();
    await fixture.session.watch();

    fixture.handle.endpoint(
      segmentId: 0,
      revision: 1,
      transcript: 'Assistant',
    );
    await _flushEvents();

    expect(
      fixture.updates.whereType<ObserverVoiceQuestionCompleted>(),
      isEmpty,
    );
    expect(
      fixture.updates.whereType<ObserverVoiceInputFailed>().single.failure.code,
      'voice_question_empty',
    );
    expect(fixture.handle.stopCalls, 1);
    await fixture.close();
  });

  test('hard deadline submits a non-empty partial exactly once', () async {
    late _FakeDeadline deadline;
    final fixture = _VoiceFixture(
      deadlineFactory: (duration, callback) {
        expect(duration, const Duration(seconds: 15));
        return deadline = _FakeDeadline(callback);
      },
    );
    await fixture.session.watch();
    fixture.handle.hypothesis(
      segmentId: 0,
      revision: 1,
      transcript: 'Assistant describe this scene',
    );
    await _flushEvents();

    deadline.fire();
    await _flushEvents();

    final question = fixture.updates.whereType<ObserverVoiceQuestionCompleted>().single;
    expect(question.question, 'describe this scene');
    expect(fixture.handle.stopCalls, 1);
    await fixture.close();
  });

  test('silence deadline fails without publishing a question', () async {
    late _FakeDeadline deadline;
    final fixture = _VoiceFixture(
      deadlineFactory: (_, callback) => deadline = _FakeDeadline(callback),
    );
    await fixture.session.watch();
    fixture.handle.hypothesis(
      segmentId: 0,
      revision: 1,
      transcript: 'Assistant',
    );
    await _flushEvents();

    deadline.fire();
    await _flushEvents();

    expect(
      fixture.updates.whereType<ObserverVoiceQuestionCompleted>(),
      isEmpty,
    );
    expect(
      fixture.updates.whereType<ObserverVoiceInputFailed>().single.failure.code,
      'voice_question_silence_timeout',
    );
    await fixture.close();
  });

  test('permission denial is retryable without duplicate capture', () async {
    final fixture = _VoiceFixture(
      permissionResults: [
        const AppError<void>(
          PermissionDeniedFailure(code: 'microphone_permission_denied'),
        ),
        const AppSuccess<void>(null),
      ],
    );

    expect(await fixture.session.watch(), isA<AppError<void>>());
    expect(fixture.recognizer.startCalls, 0);
    expect(
      fixture.updates.whereType<ObserverVoiceInputFailed>().single.failure.code,
      'microphone_permission_denied',
    );

    expect(await fixture.session.watch(), isA<AppSuccess<void>>());
    expect(fixture.permission.requestCalls, 2);
    expect(fixture.recognizer.loadCalls, 1);
    expect(fixture.recognizer.startCalls, 1);
    await fixture.close();
  });

  test('pause invalidates a queued endpoint before capture settles', () async {
    final fixture = _VoiceFixture();
    await fixture.session.watch();
    fixture.handle.hypothesis(
      segmentId: 0,
      revision: 1,
      transcript: 'Assistant ask this',
    );
    await _flushEvents();

    final pause = fixture.session.pause();
    fixture.handle.endpoint(
      segmentId: 1,
      revision: 2,
      transcript: 'late endpoint',
    );
    await pause;
    await _flushEvents();

    expect(
      fixture.updates.whereType<ObserverVoiceQuestionCompleted>(),
      isEmpty,
    );
    expect(fixture.handle.stopCalls, 1);
    await fixture.close();
  });

  test('failed stop retains native ownership and retry settles it first', () async {
    final fixture = _VoiceFixture(
      permissionResults: [
        const AppSuccess<void>(null),
        const AppSuccess<void>(null),
      ],
    );
    await fixture.session.watch();
    fixture.handle.stopResults.addAll([
      const AppError<void>(
        DeviceUnavailableFailure(code: 'microphone_stop_failed'),
      ),
      const AppSuccess<void>(null),
    ]);

    final failedPause = await fixture.session.pause();
    expect(failedPause, isA<AppError<void>>());
    expect(fixture.session.isWatching, isTrue);

    final replacement = _FakeSpeechRecognitionHandle();
    fixture.recognizer.handles.add(replacement);
    expect(await fixture.session.watch(), isA<AppSuccess<void>>());

    expect(fixture.handle.stopCalls, 2);
    expect(fixture.recognizer.startCalls, 2);
    expect(fixture.session.isWatching, isTrue);
    await fixture.close();
  });

  test('pause retries a stale in-flight start until native capture stops', () async {
    final fixture = _VoiceFixture();
    final startGate = Completer<AppResult<SpeechRecognitionHandle>>();
    final finalStopGate = Completer<AppResult<void>>();
    fixture.recognizer.onStart = () => startGate.future;
    fixture.handle.stopResults.addAll([
      const AppError<void>(
        DeviceUnavailableFailure(code: 'microphone_stop_failed'),
      ),
      finalStopGate.future,
    ]);

    final watch = fixture.session.watch();
    await _waitForCondition(() => fixture.recognizer.startCalls == 1);
    final pause = fixture.session.pause();
    var pauseCompleted = false;
    unawaited(pause.then((_) => pauseCompleted = true));

    startGate.complete(AppSuccess<SpeechRecognitionHandle>(fixture.handle));
    await _waitForCondition(() => fixture.handle.stopCalls == 2);
    expect(pauseCompleted, isFalse);
    expect(fixture.session.isWatching, isTrue);

    finalStopGate.complete(const AppSuccess<void>(null));
    expect(await pause, isA<AppSuccess<void>>());
    expect(await watch, isA<AppError<void>>());
    expect(fixture.session.isWatching, isFalse);
    await fixture.close();
  });

  test('suspend unloads native ASR after model-store suspension fails', () async {
    final fixture = _VoiceFixture();
    await fixture.session.watch();
    fixture.store.onSuspend = () async {
      throw Exception('store suspension failed');
    };

    final result = await fixture.session.suspend();

    expect(
      result,
      isA<AppError<void>>().having(
        (result) => result.failure.code,
        'code',
        'observer_voice_model_suspend_unexpected',
      ),
    );
    expect(fixture.recognizer.unloadCalls, 1);
    expect(fixture.session.isWatching, isFalse);
    await fixture.close();
  });

  test('close joins an in-flight suspension through recognizer unload', () async {
    final fixture = _VoiceFixture();
    await fixture.session.watch();
    final storeGate = Completer<void>();
    final unloadGate = Completer<AppResult<void>>();
    fixture.store.onSuspend = () => storeGate.future;
    fixture.recognizer.onUnload = () => unloadGate.future;

    final suspend = fixture.session.suspend();
    await _waitForCondition(() => fixture.store.suspendCalls == 1);
    final close = fixture.session.close();
    var closeCompleted = false;
    unawaited(close.then((_) => closeCompleted = true));
    await _flushEvents();
    expect(closeCompleted, isFalse);

    storeGate.complete();
    await _waitForCondition(() => fixture.recognizer.unloadCalls == 1);
    expect(closeCompleted, isFalse);
    unloadGate.complete(const AppSuccess<void>(null));

    expect(await suspend, isA<AppSuccess<void>>());
    expect(await close, isA<AppSuccess<void>>());
    expect(closeCompleted, isTrue);
    await fixture.close();
  });
}

final class _VoiceFixture {
  _VoiceFixture({
    List<AppResult<void>>? permissionResults,
    ObserverVoiceDeadlineFactory? deadlineFactory,
  }) : store = _FakeAsrModelStore(),
       permission = _FakeMicrophonePermissionGateway(
         permissionResults ?? [const AppSuccess<void>(null)],
       ),
       recognizer = _FakeSpeechRecognizer() {
    handle = _FakeSpeechRecognitionHandle();
    recognizer.handles.add(handle);
    session = ObserverVoiceInputSession(
      modelStore: store,
      permissionGateway: permission,
      speechRecognizer: recognizer,
      wakePhraseDetector: WakePhraseDetector('assistant'),
      questionDeadline: const Duration(seconds: 15),
      onUpdate: updates.add,
      deadlineFactory: deadlineFactory,
    );
  }

  final _FakeAsrModelStore store;
  final _FakeMicrophonePermissionGateway permission;
  final _FakeSpeechRecognizer recognizer;
  final List<ObserverVoiceInputUpdate> updates = [];
  late final _FakeSpeechRecognitionHandle handle;
  late final ObserverVoiceInputSession session;

  Future<void> close() async {
    await session.close();
    await store.close();
  }
}

final class _FakeAsrModelStore implements AsrModelStore {
  final StreamController<ModelStoreState<VerifiedAsrModelBundle>> _states = StreamController.broadcast(sync: true);
  ModelStoreState<VerifiedAsrModelBundle> _current = const ModelStoreState.idle();
  Future<void> Function()? onSuspend;
  int prepareCalls = 0;
  int suspendCalls = 0;

  @override
  ModelStoreState<VerifiedAsrModelBundle> get current => _current;

  @override
  Stream<ModelStoreState<VerifiedAsrModelBundle>> get states => _states.stream;

  @override
  Future<AppResult<VerifiedAsrModelBundle>> prepare() async {
    prepareCalls += 1;
    _current = ModelStoreState.ready(_bundle);
    _states.add(_current);
    return const AppSuccess(_bundle);
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    await onSuspend?.call();
    _current = const ModelStoreState.suspended();
    _states.add(_current);
  }

  @override
  Future<void> close() => _states.close();
}

final class _FakeMicrophonePermissionGateway implements MicrophonePermissionGateway {
  _FakeMicrophonePermissionGateway(this.results);

  final List<AppResult<void>> results;
  int requestCalls = 0;

  @override
  Future<AppResult<void>> request() async {
    requestCalls += 1;
    return results.removeAt(0);
  }
}

final class _FakeSpeechRecognizer implements SpeechRecognizer {
  final List<_FakeSpeechRecognitionHandle> handles = [];
  Future<AppResult<SpeechRecognitionHandle>> Function()? onStart;
  Future<AppResult<void>> Function()? onUnload;
  int loadCalls = 0;
  int startCalls = 0;
  int unloadCalls = 0;

  @override
  Future<AppResult<void>> loadModel(VerifiedAsrModelBundle bundle) async {
    loadCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<SpeechRecognitionHandle>> start() async {
    startCalls += 1;
    final start = onStart;
    if (start != null) return start();
    return AppSuccess<SpeechRecognitionHandle>(handles.removeAt(0));
  }

  @override
  Future<AppResult<void>> unload() async {
    unloadCalls += 1;
    return await onUnload?.call() ?? const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> close() async => const AppSuccess<void>(null);
}

final class _FakeSpeechRecognitionHandle implements SpeechRecognitionHandle {
  final StreamController<SpeechRecognitionEvent> _events = StreamController.broadcast(sync: true);
  final List<FutureOr<AppResult<void>>> stopResults = [];
  int resetCalls = 0;
  int stopCalls = 0;
  Future<AppResult<void>>? _stopTask;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  void hypothesis({
    required int segmentId,
    required int revision,
    required String transcript,
  }) {
    if (_events.isClosed) return;
    _events.add(
      SpeechRecognitionHypothesis(
        segmentId: segmentId,
        revision: revision,
        transcript: transcript,
      ),
    );
  }

  void endpoint({
    required int segmentId,
    required int revision,
    required String transcript,
  }) {
    if (_events.isClosed) return;
    _events.add(
      SpeechRecognitionEndpoint(
        segmentId: segmentId,
        revision: revision,
        transcript: transcript,
        reason: SpeechRecognitionEndpointReason.trailingSilence,
      ),
    );
  }

  void failure({
    required int segmentId,
    required int revision,
    required AppFailure failure,
  }) {
    if (_events.isClosed) return;
    _events.add(
      SpeechRecognitionFailure(
        segmentId: segmentId,
        revision: revision,
        failure: failure,
      ),
    );
  }

  @override
  Future<AppResult<void>> resetForNextSegment() async {
    resetCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> stop() {
    final activeTask = _stopTask;
    if (activeTask != null) return activeTask;
    late final Future<AppResult<void>> task;
    task = _stopOnce().then((result) {
      if (result is AppError<void> && identical(_stopTask, task)) {
        _stopTask = null;
      }
      return result;
    });
    _stopTask = task;
    return task;
  }

  Future<AppResult<void>> _stopOnce() async {
    stopCalls += 1;
    final result = stopResults.isEmpty ? const AppSuccess<void>(null) : await stopResults.removeAt(0);
    if (result is AppError<void>) return result;
    await _events.close();
    return result;
  }
}

final class _FakeDeadline implements Timer {
  _FakeDeadline(this._callback);

  final void Function() _callback;
  var _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() => _active = false;
}

Future<void> _flushEvents() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitForCondition(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected condition to become true.');
}
