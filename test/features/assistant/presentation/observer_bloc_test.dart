import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/tracked_object.dart';

import '../../../support/fake_assistant_runtime.dart';

const _testManualOptions = GenerationOptions(
  maxTokens: 32,
  temperature: 0.5,
  topP: 0.9,
  topK: 10,
  minP: 0,
);
const _testShortOptions = GenerationOptions(
  maxTokens: 16,
  temperature: 0.4,
  topP: 0.8,
  topK: 8,
  minP: 0,
);

void main() {
  test('starts with the latest scene and the ten-second default', () async {
    final scene = FakeSceneSource(current: _scene('person', id: 4));
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final timers = _TimerHarness();
    final bloc = _createBloc(scene, store, generator, timers)..add(const ObserverStarted());
    final ready = await _waitForState(
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );

    expect(ready.started, isTrue);
    expect(ready.observationEnabled, isTrue);
    expect(ready.interval, ObserverInterval.tenSeconds);
    expect(ready.scene.objects.single.label, 'person');
    expect(timers.current.duration, const Duration(seconds: 10));
    expect(store.prepareCalls, 1);

    await bloc.close();
    await scene.close();
    await store.close();
  });

  test('projects stable scene changes into state', () async {
    final fixture = await _Fixture.start();

    fixture.scene.emit(_scene('backpack', id: 9));
    final changed = await _waitForState(
      fixture.bloc,
      (state) => state.scene.objects.firstOrNull?.label == 'backpack',
    );

    expect(changed.scene.objects.single.id, 9);
    await fixture.close();
  });

  test('tick samples the latest scene and ignores overlap', () async {
    final fixture = await _Fixture.start();
    final handle = FakeGenerationHandle();
    fixture.generator.enqueueHandle(handle);
    fixture.scene.current = _scene('backpack', id: 7);

    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);
    expect(fixture.generator.requests.single.prompt, contains('center: backpack'));
    expect(
      fixture.bloc.state.activeGeneration,
      ObserverGenerationKind.automatic,
    );

    fixture.timers.current.fire();
    await _flushEvents();
    expect(fixture.generator.requests, hasLength(1));

    handle.emit('A backpack is resting nearby.');
    await _waitForState(
      fixture.bloc,
      (state) => state.automaticDraft.isNotEmpty,
    );
    handle.succeed('A backpack is resting nearby.');
    final completed = await _waitForState(
      fixture.bloc,
      (state) => state.comments.length == 1,
    );

    expect(completed.comments.single.scene.objects.single.label, 'backpack');
    expect(completed.previousComment, 'A backpack is resting nearby.');
    await fixture.close();
  });

  test('next comment receives only a successful previous comment', () async {
    final fixture = await _Fixture.start();
    final first = FakeGenerationHandle();
    final second = FakeGenerationHandle();
    fixture.generator
      ..enqueueHandle(first)
      ..enqueueHandle(second);

    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);
    first.succeed('A person is standing in view.');
    await _waitForState(fixture.bloc, (state) => state.comments.length == 1);

    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 2);
    expect(
      fixture.generator.requests.last.prompt,
      contains('Previous: A person is standing in view.'),
    );

    second.succeed('The scene remains calm and still.');
    await _waitForState(fixture.bloc, (state) => state.comments.length == 2);
    await fixture.close();
  });

  test('failure leaves previous comment unchanged and next tick retries', () async {
    final fixture = await _Fixture.start();
    final failed = FakeGenerationHandle();
    final retried = FakeGenerationHandle();
    fixture.generator
      ..enqueueHandle(failed)
      ..enqueueHandle(retried);

    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);
    failed.fail(const DeviceUnavailableFailure(code: 'observer_generation'));
    final failure = await _waitForState(
      fixture.bloc,
      (state) => state.automaticFailure != null,
    );
    expect(failure.previousComment, isNull);
    final latchedFailure = failure.automaticFailure;

    fixture.scene.emit(_scene('backpack', id: 9));
    final sceneChanged = await _waitForState(
      fixture.bloc,
      (state) => state.scene.objects.firstOrNull?.label == 'backpack',
    );
    expect(sceneChanged.automaticFailure, same(latchedFailure));

    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 2);
    expect(fixture.bloc.state.automaticFailure, isNull);
    retried.succeed('A person is visible in the center.');
    await _waitForState(fixture.bloc, (state) => state.comments.length == 1);
    await fixture.close();
  });

  test('stop cancels timer and active automatic generation', () async {
    final fixture = await _Fixture.start();
    final handle = FakeGenerationHandle();
    fixture.generator.enqueueHandle(handle);
    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);

    fixture.bloc.add(const ObservationStopped());
    final stopped = await _waitForState(
      fixture.bloc,
      (state) => !state.observationEnabled && state.activeGeneration == null,
    );

    expect(stopped.activeGeneration, isNull);
    expect(fixture.timers.current.isActive, isFalse);
    expect(handle.cancelCalls, 1);
    expect(stopped.comments, isEmpty);
    fixture.timers.current.fire();
    await _flushEvents();
    expect(fixture.generator.requests, hasLength(1));
    await fixture.close();
  });

  test('stop acknowledges quiescence only after cancellation settles', () async {
    final fixture = await _Fixture.start();
    final cancellation = Completer<void>();
    final handle = FakeGenerationHandle()..onCancel = () => cancellation.future;
    fixture.generator.enqueueHandle(handle);
    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);

    fixture.bloc.add(const ObservationStopped());
    final disabling = await _waitForState(
      fixture.bloc,
      (state) => !state.observationEnabled,
    );
    expect(disabling.activeGeneration, ObserverGenerationKind.automatic);
    expect(handle.cancelCalls, 1);
    var quiesced = false;
    final quiescence = _waitForState(
      fixture.bloc,
      (state) => !state.observationEnabled && state.activeGeneration == null,
    ).then((_) => quiesced = true);
    await _flushEvents();
    expect(quiesced, isFalse);

    cancellation.complete();
    await quiescence;
    expect(quiesced, isTrue);
    await fixture.close();
  });

  test('selecting an interval replaces the timer without persistence', () async {
    final fixture = await _Fixture.start();
    final originalTimer = fixture.timers.current;

    fixture.bloc.add(
      const ObservationIntervalSelected(ObserverInterval.twoMinutes),
    );
    final changed = await _waitForState(
      fixture.bloc,
      (state) => state.interval == ObserverInterval.twoMinutes,
    );

    expect(changed.interval.duration, const Duration(minutes: 2));
    expect(originalTimer.isActive, isFalse);
    expect(fixture.timers.current.duration, const Duration(minutes: 2));
    await fixture.close();
  });

  test('manual request preempts automatic work and blocks timer ticks', () async {
    final fixture = await _Fixture.start();
    final automatic = FakeGenerationHandle();
    final manual = FakeGenerationHandle();
    fixture.generator
      ..enqueueHandle(automatic)
      ..enqueueHandle(manual);
    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);

    fixture.bloc.add(const ObserverPromptSubmitted('What do you see?'));
    await _waitForRequests(fixture.generator, 2);
    expect(automatic.cancelCalls, 1);
    expect(
      fixture.bloc.state.activeGeneration,
      ObserverGenerationKind.manual,
    );
    expect(fixture.generator.requests.last.prompt, contains('What do you see?'));

    fixture.timers.current.fire();
    await _flushEvents();
    expect(fixture.generator.requests, hasLength(2));

    manual.succeed('I see one person in the center.');
    final completed = await _waitForState(
      fixture.bloc,
      (state) => state.messages.length == 2,
    );
    expect(completed.messages.last.content, 'I see one person in the center.');
    expect(completed.comments, isEmpty);
    await fixture.close();
  });

  test('automatic request includes the newest four completed dialogue pairs', () async {
    final fixture = await _Fixture.start();
    for (var turn = 1; turn <= 5; turn += 1) {
      final handle = FakeGenerationHandle();
      fixture.generator.enqueueHandle(handle);
      fixture.bloc.add(ObserverPromptSubmitted('question $turn'));
      await _waitForRequests(fixture.generator, turn);
      handle.succeed('answer $turn');
      await _waitForState(
        fixture.bloc,
        (state) => state.messages.length == turn * 2,
      );
    }
    final automatic = FakeGenerationHandle();
    fixture.generator.enqueueHandle(automatic);

    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 6);
    final prompt = fixture.generator.requests.last.prompt;

    expect(prompt, isNot(contains('question 1')));
    for (var turn = 2; turn <= 5; turn += 1) {
      expect(prompt, contains('question $turn'));
      expect(prompt, contains('answer $turn'));
    }
    automatic.succeed('The current scene remains visible.');
    await _waitForState(fixture.bloc, (state) => state.comments.length == 1);
    await fixture.close();
  });

  test('manual request includes the newest four completed dialogue pairs', () async {
    final fixture = await _Fixture.start();
    for (var turn = 1; turn <= 5; turn += 1) {
      final handle = FakeGenerationHandle();
      fixture.generator.enqueueHandle(handle);
      fixture.bloc.add(ObserverPromptSubmitted('question $turn'));
      await _waitForRequests(fixture.generator, turn);
      handle.succeed('answer $turn');
      await _waitForState(
        fixture.bloc,
        (state) => state.messages.length == turn * 2,
      );
    }
    final sixth = FakeGenerationHandle();
    fixture.generator.enqueueHandle(sixth);

    fixture.bloc.add(const ObserverPromptSubmitted('question 6'));
    await _waitForRequests(fixture.generator, 6);
    final prompt = fixture.generator.requests.last.prompt;

    expect(prompt, isNot(contains('question 1')));
    for (var turn = 2; turn <= 5; turn += 1) {
      expect(prompt, contains('question $turn'));
      expect(prompt, contains('answer $turn'));
    }
    sixth.succeed('answer 6');
    await _waitForState(fixture.bloc, (state) => state.messages.length == 12);
    await fixture.close();
  });

  test('manual cancellation discards its uncommitted turn', () async {
    final fixture = await _Fixture.start();
    final handle = FakeGenerationHandle();
    fixture.generator.enqueueHandle(handle);

    fixture.bloc.add(const ObserverPromptSubmitted('Cancel this'));
    await _waitForRequests(fixture.generator, 1);
    handle.emit('Uncommitted');
    await _waitForState(
      fixture.bloc,
      (state) => state.manualDraftResponse.isNotEmpty,
    );
    fixture.bloc.add(const ObserverManualGenerationCancelled());
    final cancelled = await _waitForState(
      fixture.bloc,
      (state) => state.activeGeneration == null,
    );

    expect(cancelled.messages, isEmpty);
    expect(cancelled.manualDraftPrompt, isEmpty);
    expect(cancelled.manualDraftResponse, isEmpty);
    expect(handle.cancelCalls, 1);
    await fixture.close();
  });

  test('lifecycle preserves observer preference, interval, and transcript', () async {
    final fixture = await _Fixture.start();
    final handle = FakeGenerationHandle();
    fixture.generator.enqueueHandle(handle);
    fixture.bloc.add(
      const ObservationIntervalSelected(ObserverInterval.thirtySeconds),
    );
    await _waitForState(
      fixture.bloc,
      (state) => state.interval == ObserverInterval.thirtySeconds,
    );
    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);
    handle.succeed('A person remains visible near the center.');
    await _waitForState(fixture.bloc, (state) => state.comments.length == 1);

    fixture.bloc.add(const ObserverForegroundDeactivated());
    await _waitForState(
      fixture.bloc,
      (state) => !state.foregroundActive,
    );
    expect(fixture.timers.current.isActive, isFalse);
    fixture.bloc.add(const ObserverSuspended());
    await _waitForState(
      fixture.bloc,
      (state) => state.modelStatus == ObserverModelStatus.suspended,
    );
    await _flushEvents();
    expect(fixture.store.suspendCalls, 1);

    fixture.bloc.add(const ObserverResumed());
    final resumed = await _waitForState(
      fixture.bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    expect(resumed.foregroundActive, isTrue);
    expect(resumed.observationEnabled, isTrue);
    expect(resumed.interval, ObserverInterval.thirtySeconds);
    expect(resumed.comments, hasLength(1));
    expect(fixture.timers.current.duration, const Duration(seconds: 30));
    expect(fixture.store.prepareCalls, 2);
    await fixture.close();
  });

  test('resume reconciles preparation completed before suspension', () async {
    final preparation = Completer<AppResult<VerifiedModelArtifact>>();
    final scene = FakeSceneSource(current: _scene('person', id: 1));
    final store = FakeAssistantModelStore(onPrepare: () => preparation.future);
    final generator = FakeCommentGenerator();
    final timers = _TimerHarness();
    final bloc = _createBloc(scene, store, generator, timers)..add(const ObserverStarted());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.loading,
    );

    bloc.add(const ObserverForegroundDeactivated());
    await _waitForState(bloc, (state) => !state.foregroundActive);
    store.emit(ModelStoreState.ready(testQwenArtifact));
    preparation.complete(const AppSuccess(testQwenArtifact));
    await _flushEvents();

    bloc.add(const ObserverResumed());
    final resumed = await _waitForState(
      bloc,
      (state) => state.foregroundActive && state.modelStatus == ObserverModelStatus.ready,
    );

    expect(resumed.observationEnabled, isTrue);
    expect(store.prepareCalls, 1);
    expect(timers.current.isActive, isTrue);
    await bloc.close();
    await scene.close();
    await store.close();
  });

  test('close cancels timer, subscription, and active generation', () async {
    final fixture = await _Fixture.start();
    final handle = FakeGenerationHandle();
    fixture.generator.enqueueHandle(handle);
    fixture.timers.current.fire();
    await _waitForRequests(fixture.generator, 1);

    await fixture.bloc.close();
    expect(fixture.timers.current.isActive, isFalse);
    expect(handle.cancelCalls, 1);

    fixture.scene.emit(_scene('backpack', id: 12));
    await _flushEvents();
    expect(fixture.bloc.isClosed, isTrue);
    await fixture.scene.close();
    await fixture.store.close();
  });
}

final class _Fixture {
  _Fixture._({
    required this.scene,
    required this.store,
    required this.generator,
    required this.timers,
    required this.bloc,
  });

  final FakeSceneSource scene;
  final FakeAssistantModelStore store;
  final FakeCommentGenerator generator;
  final _TimerHarness timers;
  final ObserverBloc bloc;

  static Future<_Fixture> start() async {
    final scene = FakeSceneSource(current: _scene('person', id: 1));
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final timers = _TimerHarness();
    final bloc = _createBloc(scene, store, generator, timers)..add(const ObserverStarted());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    return _Fixture._(
      scene: scene,
      store: store,
      generator: generator,
      timers: timers,
      bloc: bloc,
    );
  }

  Future<void> close() async {
    await bloc.close();
    await scene.close();
    await store.close();
  }
}

ObserverBloc _createBloc(
  FakeSceneSource scene,
  FakeAssistantModelStore store,
  FakeCommentGenerator generator,
  _TimerHarness timers,
) {
  return ObserverBloc(
    sceneSource: scene,
    modelStore: store,
    commentGenerator: generator,
    requestBuilder: ObserverRequestBuilder(
      qwenPromptBuilder: QwenPromptBuilder(
        systemPrompt: 'You are a concise local observer.',
        manualOptions: _testManualOptions,
        shortCommentOptions: _testShortOptions,
      ),
    ),
    periodicTimerFactory: timers.create,
  );
}

SceneSnapshot _scene(String label, {required int id}) {
  return SceneSnapshot(
    objects: [
      TrackedObject(
        id: id,
        classId: id,
        label: label,
        region: SceneRegion.center,
      ),
    ],
  );
}

Future<ObserverState> _waitForState(
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate,
) async {
  if (predicate(bloc.state)) return bloc.state;
  return bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 2));
}

Future<void> _waitForRequests(
  FakeCommentGenerator generator,
  int count,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (generator.requests.length >= count) return;
    await _flushEvents();
  }
  fail('Expected $count generation requests, got ${generator.requests.length}.');
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _TimerHarness {
  final List<_FakePeriodicTimer> created = [];

  _FakePeriodicTimer get current => created.last;

  Timer create(Duration duration, void Function() onTick) {
    final timer = _FakePeriodicTimer(duration, onTick);
    created.add(timer);
    return timer;
  }
}

final class _FakePeriodicTimer implements Timer {
  _FakePeriodicTimer(this.duration, this._onTick);

  final Duration duration;
  final void Function() _onTick;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  void fire() {
    if (!_active) return;
    _tick += 1;
    _onTick();
  }

  @override
  void cancel() {
    _active = false;
  }
}
