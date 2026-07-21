import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/pages/assistant_page.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_timer_controller.dart';
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
const _testShortCommentOptions = GenerationOptions(
  maxTokens: 16,
  temperature: 0.4,
  topP: 0.8,
  topK: 8,
  minP: 0,
);

void main() {
  testWidgets('renders loading, download, verification, and ready states', (
    tester,
  ) async {
    final loadingGate = Completer<void>();
    final downloadGate = Completer<void>();
    final verificationGate = Completer<void>();
    late final FakeAssistantModelStore store;
    store = FakeAssistantModelStore(
      onPrepare: () async {
        store.emit(const QwenModelStoreState.loading());
        await loadingGate.future;
        store.emit(const QwenModelStoreState.downloading(0.37));
        await downloadGate.future;
        store.emit(const QwenModelStoreState.verifying());
        await verificationGate.future;
        store.emit(QwenModelStoreState.ready(testQwenArtifact));
        return const AppSuccess(testQwenArtifact);
      },
    );
    final bloc = _createBloc(store, FakeCommentGenerator())..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.loading,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    expect(find.text('Preparing the local Qwen model…'), findsOneWidget);
    expect(find.byKey(assistantPromptFieldKey), findsNothing);

    loadingGate.complete();
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.downloading,
    );
    expect(find.text('Downloading the Qwen model: 37%'), findsOneWidget);

    downloadGate.complete();
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.verifying,
    );
    expect(find.text('Verifying the local Qwen model…'), findsOneWidget);

    verificationGate.complete();
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    expect(find.text('Your on-device assistant is ready'), findsOneWidget);
    expect(find.byKey(assistantPromptFieldKey), findsOneWidget);

    await _disposeFixture(tester, bloc, store);
  });

  testWidgets('shows actionable network failure and retries model preparation', (
    tester,
  ) async {
    const failure = NetworkFailure(code: 'model_download');
    late final FakeAssistantModelStore store;
    store = FakeAssistantModelStore(
      onPrepare: () async {
        if (store.prepareCalls == 1) {
          store.emit(QwenModelStoreState.failure(failure));
          return const AppError(failure);
        }
        store.emit(QwenModelStoreState.ready(testQwenArtifact));
        return const AppSuccess(testQwenArtifact);
      },
    );
    final bloc = _createBloc(store, FakeCommentGenerator())..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.failure,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    expect(
      find.text(
        'The Qwen model could not be downloaded. Check your connection and retry.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(assistantModelRetryButtonKey), findsOneWidget);

    await _tapVisible(tester, find.byKey(assistantModelRetryButtonKey));
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );

    expect(store.prepareCalls, 2);
    expect(find.text('Your on-device assistant is ready'), findsOneWidget);

    await _disposeFixture(tester, bloc, store);
  });

  testWidgets('streams and commits a manual answer on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    generator.enqueueHandle(handle);
    final bloc = _createBloc(store, generator)..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    expect(
      find.bySemanticsLabel('Message to the local assistant'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(assistantPromptFieldKey),
      'Explain the scene',
    );
    await tester.pump();
    await _tapVisible(tester, find.byKey(assistantSubmitControlKey));
    await _pumpUntil(tester, () => generator.requests.length == 1);

    expect(find.text('Explain the scene'), findsOneWidget);
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.bySemanticsLabel('Stop'), findsWidgets);

    await tester.runAsync(() async {
      handle
        ..emit('Streaming ')
        ..emit('answer')
        ..succeed('Streaming answer');
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(tester, bloc, (state) => state.messages.length == 2);

    expect(find.text('Streaming answer'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);

    semantics.dispose();
    await _disposeFixture(tester, bloc, store);
  });

  testWidgets('Stop discards the visible draft and restores the empty state', (
    tester,
  ) async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    generator.enqueueHandle(handle);
    final bloc = _createBloc(store, generator)..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    await tester.enterText(
      find.byKey(assistantPromptFieldKey),
      'Cancel this answer',
    );
    await tester.pump();
    await _tapVisible(tester, find.byKey(assistantSubmitControlKey));
    await _pumpUntil(tester, () => generator.requests.length == 1);
    handle.emit('Uncommitted prefix');
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.manualDraftResponse == 'Uncommitted prefix',
    );

    await _tapVisible(tester, find.byKey(assistantSubmitControlKey));
    await tester.runAsync(() async {
      await handle.cancel();
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.activeGeneration == null,
    );

    expect(handle.cancelCalls, 1);
    expect(find.text('Cancel this answer'), findsNothing);
    expect(find.text('Uncommitted prefix'), findsNothing);
    expect(find.text('Your on-device assistant is ready'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);

    await _disposeFixture(tester, bloc, store);
  });

  testWidgets('offers answer retry and resubmits the failed prompt', (
    tester,
  ) async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final failedHandle = FakeGenerationHandle();
    final retryHandle = FakeGenerationHandle();
    generator
      ..enqueueHandle(failedHandle)
      ..enqueueHandle(retryHandle);
    final bloc = _createBloc(store, generator)..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    await tester.enterText(
      find.byKey(assistantPromptFieldKey),
      'Retry this prompt',
    );
    await tester.pump();
    await _tapVisible(tester, find.byKey(assistantSubmitControlKey));
    await _pumpUntil(tester, () => generator.requests.length == 1);
    await tester.runAsync(() async {
      failedHandle.fail(
        const DeviceUnavailableFailure(code: 'assistant_generation'),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.manualFailure != null,
    );

    expect(
      find.text('The local assistant could not finish this answer.'),
      findsOneWidget,
    );
    expect(find.byKey(assistantAnswerRetryButtonKey), findsOneWidget);

    await tester.ensureVisible(find.byKey(assistantAnswerRetryButtonKey));
    await _tapVisible(tester, find.byKey(assistantAnswerRetryButtonKey));
    await _pumpUntil(tester, () => generator.requests.length == 2);
    await tester.runAsync(() async {
      retryHandle.succeed('Recovered in the UI');
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(tester, bloc, (state) => state.messages.length == 2);

    expect(generator.requests[1].prompt, generator.requests[0].prompt);
    expect(find.text('Recovered in the UI'), findsOneWidget);

    await _disposeFixture(tester, bloc, store);
  });

  testWidgets('shows scene, interval controls, and automatic streaming', (
    tester,
  ) async {
    const objectLabel = 'person';
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    final scene = FakeSceneSource(
      current: SceneSnapshot(
        objects: const [
          TrackedObject(
            id: 3,
            classId: 0,
            label: objectLabel,
            region: SceneRegion.center,
          ),
        ],
      ),
    );
    late void Function() fireTick;
    final bloc = _createBloc(
      store,
      generator,
      sceneSource: scene,
      periodicTimerFactory: (_, onTick) {
        fireTick = onTick;
        return _DormantTimer();
      },
    )..add(const ObserverStarted());
    generator.enqueueHandle(handle);
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    expect(find.text('Automatic observer'), findsOneWidget);
    expect(find.text('person #3 · center'), findsOneWidget);
    expect(find.text('Watching every 10 seconds'), findsOneWidget);

    fireTick();
    await _pumpUntil(tester, () => generator.requests.length == 1);
    handle.emit('A person is standing');
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.automaticDraft.isNotEmpty,
    );
    expect(find.text('A person is standing'), findsOneWidget);

    await tester.runAsync(() async {
      handle.succeed('A person is standing in the center.');
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(tester, bloc, (state) => state.comments.length == 1);
    expect(find.text('A person is standing in the center.'), findsOneWidget);

    await tester.ensureVisible(find.text('30s'));
    await _tapVisible(tester, find.text('30s'));
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.interval.seconds == 30,
    );
    expect(find.text('Watching every 30 seconds'), findsOneWidget);

    await tester.ensureVisible(find.byKey(observerToggleButtonKey));
    await _tapVisible(tester, find.byKey(observerToggleButtonKey));
    await _pumpUntilState(tester, bloc, (state) => !state.observationEnabled);
    expect(find.text('Automatic observation is stopped.'), findsOneWidget);

    await _disposeFixture(tester, bloc, store);
    await scene.close();
  });

  testWidgets('stops, replays, and mutes completed observer speech', (
    tester,
  ) async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    final speech = FakeSpeechSynthesizer();
    final automaticSpeech = FakeSpeechAttempt();
    late void Function() fireTick;
    speech.enqueueAttempt(automaticSpeech);
    generator.enqueueHandle(handle);
    final bloc = _createBloc(
      store,
      generator,
      speechSynthesizer: speech,
      periodicTimerFactory: (_, onTick) {
        fireTick = onTick;
        return _DormantTimer();
      },
    )..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    fireTick();
    await _pumpUntil(tester, () => generator.requests.length == 1);
    await tester.runAsync(() async {
      handle.succeed('A completed spoken comment.');
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.comments.length == 1 && state.isSpeaking,
    );

    expect(speech.spokenTexts, ['A completed spoken comment.']);
    final commentControl = find.byKey(observerCommentSpeechButtonKey(0));
    await tester.ensureVisible(commentControl);
    expect(find.descendant(of: commentControl, matching: find.text('Stop')), findsOneWidget);

    await _tapVisible(tester, commentControl);
    await _pumpUntilState(tester, bloc, (state) => !state.isSpeaking);
    expect(speech.stopCalls, 1);
    expect(find.descendant(of: commentControl, matching: find.text('Replay')), findsOneWidget);

    final replaySpeech = FakeSpeechAttempt();
    speech.enqueueAttempt(replaySpeech);
    await _tapVisible(tester, commentControl);
    await _pumpUntilState(tester, bloc, (state) => state.isSpeaking);
    expect(speech.spokenTexts, [
      'A completed spoken comment.',
      'A completed spoken comment.',
    ]);

    final muteControl = find.byKey(observerSpeechMuteButtonKey);
    await tester.ensureVisible(muteControl);
    await _tapVisible(tester, muteControl);
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.speechMuted && !state.isSpeaking,
    );
    expect(speech.stopCalls, 2);

    await _tapVisible(tester, muteControl);
    await _pumpUntilState(tester, bloc, (state) => !state.speechMuted);
    expect(speech.spokenTexts, hasLength(2));

    await _disposeFixture(tester, bloc, store);
  });

  testWidgets('keeps a prompt when speech preemption needs recovery', (
    tester,
  ) async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final automatic = FakeGenerationHandle();
    final manual = FakeGenerationHandle();
    final speech = FakeSpeechSynthesizer();
    final speechAttempt = FakeSpeechAttempt();
    late void Function() fireTick;
    var stopAttempt = 0;
    generator
      ..enqueueHandle(automatic)
      ..enqueueHandle(manual);
    speech
      ..enqueueAttempt(speechAttempt)
      ..onStop = () async {
        stopAttempt += 1;
        if (stopAttempt == 1) {
          return const AppError<void>(
            DeviceUnavailableFailure(code: 'speech_stop_failed'),
          );
        }
        return const AppSuccess<void>(null);
      };
    final bloc = _createBloc(
      store,
      generator,
      speechSynthesizer: speech,
      periodicTimerFactory: (_, onTick) {
        fireTick = onTick;
        return _DormantTimer();
      },
    )..add(const ObserverStarted());
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await tester.pumpWidget(_TestAssistantApp(bloc: bloc));

    fireTick();
    await _pumpUntil(tester, () => generator.requests.length == 1);
    await tester.runAsync(() async {
      automatic.succeed('Speech must stop before the manual request.');
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(tester, bloc, (state) => state.isSpeaking);

    await tester.enterText(
      find.byKey(assistantPromptFieldKey),
      'Do not lose this prompt',
    );
    await tester.pump();
    await _tapVisible(tester, find.byKey(assistantSubmitControlKey));
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.speechFailure != null,
    );

    final promptField = tester.widget<CupertinoTextField>(
      find.byKey(assistantPromptFieldKey),
    );
    expect(promptField.controller?.text, 'Do not lose this prompt');
    expect(generator.requests, hasLength(1));
    expect(
      find.text(
        "Speech playback failed. Use the comment's speech control to recover.",
      ),
      findsOneWidget,
    );
    final commentControl = find.byKey(observerCommentSpeechButtonKey(0));
    await tester.ensureVisible(commentControl);
    expect(
      find.descendant(of: commentControl, matching: find.text('Stop')),
      findsOneWidget,
    );

    await _tapVisible(tester, commentControl);
    await _pumpUntilState(
      tester,
      bloc,
      (state) => !state.isSpeaking && state.speechFailure == null,
    );
    await _tapVisible(tester, find.byKey(assistantSubmitControlKey));
    await _pumpUntilState(
      tester,
      bloc,
      (state) => state.activeGeneration == ObserverGenerationKind.manual,
    );

    expect(generator.requests, hasLength(2));
    expect(promptField.controller?.text, isEmpty);
    await tester.runAsync(() async {
      manual.succeed('The preserved prompt was accepted.');
      await Future<void>.delayed(Duration.zero);
    });
    await _pumpUntilState(tester, bloc, (state) => state.messages.length == 2);
    await _disposeFixture(tester, bloc, store);
  });
}

final class _TestAssistantApp extends StatelessWidget {
  const _TestAssistantApp({required this.bloc});

  final ObserverBloc bloc;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: BlocProvider.value(
        value: bloc,
        child: const AssistantPage(),
      ),
    );
  }
}

ObserverBloc _createBloc(
  FakeAssistantModelStore store,
  FakeCommentGenerator generator, {
  FakeSceneSource? sceneSource,
  FakeSpeechSynthesizer? speechSynthesizer,
  ObserverPeriodicTimerFactory? periodicTimerFactory,
}) {
  return ObserverBloc(
    generation: ObserverGenerationDependencies(
      sceneSource: sceneSource ?? FakeSceneSource(),
      qwenModelStore: store,
      commentGenerator: generator,
      requestBuilder: ObserverRequestBuilder(
        qwenPromptBuilder: QwenPromptBuilder(
          systemPrompt: 'You are a concise local assistant.',
          dialogueOptions: _testManualOptions,
          shortCommentOptions: _testShortCommentOptions,
        ),
      ),
    ),
    voice: ObserverVoiceDependencies(
      asrModelStore: FakeAsrModelStore(),
      microphonePermissionGateway: FakeMicrophonePermissionGateway(),
      speechRecognizer: FakeSpeechRecognizer(),
      speechSynthesizer: speechSynthesizer ?? FakeSpeechSynthesizer(),
      wakePhrase: 'assistant',
      questionDeadline: testVoiceQuestionDeadline,
    ),
    periodicTimerFactory: periodicTimerFactory ?? (_, _) => _DormantTimer(),
  );
}

final class _DormantTimer implements Timer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

Future<void> _pumpUntilState(
  WidgetTester tester,
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate,
) async {
  try {
    await _pumpUntil(tester, () => predicate(bloc.state));
  } on TestFailure {
    final state = bloc.state;
    throw TestFailure(
      'Condition did not become true. '
      'model=${state.modelStatus}, voice=${state.voicePhase}, '
      'generation=${state.activeGeneration}, speaking=${state.isSpeaking}, '
      'comments=${state.comments.length}, messages=${state.messages.length}.',
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump(AppAnimations.regular.fast);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (predicate()) {
      await tester.pump();
      return;
    }
  }
  throw TestFailure('Condition did not become true.');
}

Future<void> _disposeFixture(
  WidgetTester tester,
  ObserverBloc bloc,
  FakeAssistantModelStore store,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(bloc.close);
  await tester.runAsync(store.close);
}
