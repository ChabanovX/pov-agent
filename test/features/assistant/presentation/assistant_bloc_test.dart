import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_state.dart';
import 'package:pov_agent/features/assistant/presentation/services/assistant_generation_runner.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

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
  test('stays idle until the router explicitly starts the assistant', () async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final bloc = _createBloc(store, generator);

    await pumpEventQueue();

    expect(bloc.state.started, isFalse);
    expect(bloc.state.modelStatus, AssistantModelStatus.idle);
    expect(store.prepareCalls, 0);

    await bloc.close();
    expect(store.closeCalls, 0);
    expect(generator.closeCalls, 0);
    await store.close();
  });

  test('shares start and projects download, verification, and ready phases', () async {
    final downloadGate = Completer<void>();
    late final FakeAssistantModelStore store;
    store = FakeAssistantModelStore(
      onPrepare: () async {
        store
          ..emit(const ModelStoreState.loading())
          ..emit(const ModelStoreState.downloading(0.42));
        await downloadGate.future;
        store.emit(const ModelStoreState.verifying());
        await Future<void>.delayed(Duration.zero);
        store.emit(ModelStoreState.ready(testQwenArtifact));
        return const AppSuccess(testQwenArtifact);
      },
    );
    final bloc = _createBloc(store, FakeCommentGenerator());
    final statuses = <AssistantModelStatus>[];
    final subscription = bloc.stream.listen(
      (state) => statuses.add(state.modelStatus),
    );

    bloc
      ..add(const AssistantStarted())
      ..add(const AssistantStarted());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == AssistantModelStatus.downloading,
    );

    expect(store.prepareCalls, 1);
    expect(bloc.state.modelDownloadProgress, 0.42);

    downloadGate.complete();
    await _waitForState(
      bloc,
      (state) => state.modelStatus == AssistantModelStatus.ready,
    );

    expect(statuses, contains(AssistantModelStatus.verifying));
    expect(bloc.state.modelDownloadProgress, isNull);

    await subscription.cancel();
    await bloc.close();
    await store.close();
  });

  test('keeps model failure actionable and ignores overlapping retries', () async {
    const failure = NetworkFailure(code: 'model_download');
    late final FakeAssistantModelStore store;
    store = FakeAssistantModelStore(
      onPrepare: () async {
        if (store.prepareCalls == 1) {
          store.emit(ModelStoreState.failure(failure));
          return const AppError(failure);
        }
        store.emit(ModelStoreState.ready(testQwenArtifact));
        return const AppSuccess(testQwenArtifact);
      },
    );
    final bloc = _createBloc(store, FakeCommentGenerator())..add(const AssistantStarted());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == AssistantModelStatus.failure,
    );

    expect(bloc.state.modelFailure, same(failure));

    bloc
      ..add(const AssistantModelRetryRequested())
      ..add(const AssistantModelRetryRequested());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == AssistantModelStatus.ready,
    );

    expect(store.prepareCalls, 2);

    await bloc.close();
    await store.close();
  });

  test('streams a /think answer before committing the complete turn', () async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    generator.enqueueHandle(handle);
    final bloc = _createBloc(store, generator)..add(const AssistantStarted());
    await _waitForReady(bloc);
    final draftStates = <String>[];
    final subscription = bloc.stream.listen(
      (state) => draftStates.add(state.draftResponse),
    );

    bloc.add(const AssistantPromptSubmitted('  What can you infer?  '));
    await _waitForState(
      bloc,
      (state) => state.generationStatus == AssistantGenerationStatus.generating,
    );
    await _waitForCondition(() => generator.requests.length == 1);

    final request = generator.requests.single;
    expect(request.prompt, contains('\n/think<|im_end|>'));
    expect(request.prompt, endsWith('<|im_start|>assistant\n<think>\n'));
    expect(request.startsInsideReasoning, isTrue);

    handle
      ..emit('A visible')
      ..emit(' answer')
      ..succeed('A visible answer');
    await _waitForState(bloc, (state) => state.messages.length == 2);

    expect(draftStates, contains('A visible answer'));
    expect(bloc.state.messages[0].content, 'What can you infer?');
    expect(bloc.state.messages[1].content, 'A visible answer');
    expect(bloc.state.draftPrompt, isEmpty);
    expect(bloc.state.draftResponse, isEmpty);

    await subscription.cancel();
    await bloc.close();
    await store.close();
  });

  test('rejects empty, oversized, not-ready, and overlapping prompts', () async {
    final preparationGate = Completer<void>();
    late final FakeAssistantModelStore store;
    store = FakeAssistantModelStore(
      onPrepare: () async {
        await preparationGate.future;
        store.emit(ModelStoreState.ready(testQwenArtifact));
        return const AppSuccess(testQwenArtifact);
      },
    );
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    generator.enqueueHandle(handle);
    final bloc = _createBloc(store, generator)
      ..add(const AssistantStarted())
      ..add(const AssistantPromptSubmitted('not ready'));
    await pumpEventQueue();
    expect(generator.requests, isEmpty);

    preparationGate.complete();
    await _waitForReady(bloc);
    bloc
      ..add(const AssistantPromptSubmitted('   '))
      ..add(
        AssistantPromptSubmitted(
          'x' * (AssistantBloc.manualPromptCharacterLimit + 1),
        ),
      )
      ..add(const AssistantPromptSubmitted('first'))
      ..add(const AssistantPromptSubmitted('overlap'));
    await _waitForCondition(() => generator.requests.length == 1);

    expect(generator.requests.single.prompt, contains('\nfirst\n/think'));

    bloc.add(const AssistantGenerationCancelled());
    await _waitForState(
      bloc,
      (state) => state.generationStatus == AssistantGenerationStatus.idle,
    );
    await bloc.close();
    await store.close();
  });

  test('cancellation discards the prompt and visible response prefix', () async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    final cancellationGate = Completer<void>();
    handle.onCancel = () => cancellationGate.future;
    generator.enqueueHandle(handle);
    final bloc = _createBloc(store, generator)..add(const AssistantStarted());
    await _waitForReady(bloc);

    bloc.add(const AssistantPromptSubmitted('Discard this turn'));
    await _waitForCondition(() => generator.requests.length == 1);
    handle.emit('Incomplete prefix');
    await _waitForState(
      bloc,
      (state) => state.draftResponse == 'Incomplete prefix',
    );

    bloc.add(const AssistantGenerationCancelled());
    await _waitForCondition(() => handle.cancelCalls == 1);
    handle.emit(' ignored late chunk');
    await pumpEventQueue();
    expect(bloc.state.draftResponse, 'Incomplete prefix');

    cancellationGate.complete();
    await _waitForState(
      bloc,
      (state) => state.generationStatus == AssistantGenerationStatus.idle,
    );

    expect(handle.cancelCalls, 1);
    expect(bloc.state.messages, isEmpty);
    expect(bloc.state.draftPrompt, isEmpty);
    expect(bloc.state.draftResponse, isEmpty);

    await bloc.close();
    await store.close();
  });

  test('answer retry resubmits the failed prompt without committing its prefix', () async {
    const failure = DeviceUnavailableFailure(code: 'assistant_generation');
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final firstHandle = FakeGenerationHandle();
    final retryHandle = FakeGenerationHandle();
    generator
      ..enqueueHandle(firstHandle)
      ..enqueueHandle(retryHandle);
    final bloc = _createBloc(store, generator)..add(const AssistantStarted());
    await _waitForReady(bloc);

    bloc.add(const AssistantPromptSubmitted('Try this again'));
    await _waitForCondition(() => generator.requests.length == 1);
    firstHandle
      ..emit('Uncommitted')
      ..fail(failure);
    await _waitForState(
      bloc,
      (state) => state.generationStatus == AssistantGenerationStatus.failure,
    );

    expect(bloc.state.messages, isEmpty);
    expect(bloc.state.draftPrompt, 'Try this again');
    expect(bloc.state.generationFailure, same(failure));

    bloc.add(const AssistantAnswerRetryRequested());
    await _waitForCondition(() => generator.requests.length == 2);
    expect(generator.requests[1].prompt, generator.requests[0].prompt);

    retryHandle.succeed('Recovered answer');
    await _waitForState(bloc, (state) => state.messages.length == 2);
    expect(bloc.state.messages[1].content, 'Recovered answer');

    await bloc.close();
    await store.close();
  });

  test('keeps full transcript visible but sends only the latest completed turn', () async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final bloc = _createBloc(store, generator)..add(const AssistantStarted());
    await _waitForReady(bloc);

    for (var turn = 1; turn <= 3; turn += 1) {
      final handle = FakeGenerationHandle();
      generator.enqueueHandle(handle);
      bloc.add(AssistantPromptSubmitted('question $turn'));
      await _waitForCondition(() => generator.requests.length == turn);
      handle.succeed('answer $turn');
      await _waitForState(bloc, (state) => state.messages.length == turn * 2);
    }

    final fourthHandle = FakeGenerationHandle();
    generator.enqueueHandle(fourthHandle);
    bloc.add(const AssistantPromptSubmitted('question 4'));
    await _waitForCondition(() => generator.requests.length == 4);
    final prompt = generator.requests.last.prompt;

    expect(bloc.state.messages, hasLength(6));
    expect(prompt, isNot(contains('question 1')));
    expect(prompt, isNot(contains('answer 1')));
    expect(prompt, isNot(contains('question 2')));
    expect(prompt, isNot(contains('answer 2')));
    expect(prompt, contains('question 3'));
    expect(prompt, contains('answer 3'));
    expect(prompt, contains('question 4'));

    bloc.add(const AssistantGenerationCancelled());
    await _waitForState(
      bloc,
      (state) => state.generationStatus == AssistantGenerationStatus.idle,
    );
    await bloc.close();
    await store.close();
  });

  test('suspend cancels drafts, retains transcript, and resume prepares again', () async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final committedHandle = FakeGenerationHandle();
    final activeHandle = FakeGenerationHandle();
    generator
      ..enqueueHandle(committedHandle)
      ..enqueueHandle(activeHandle);
    final bloc = _createBloc(store, generator)..add(const AssistantStarted());
    await _waitForReady(bloc);

    bloc.add(const AssistantPromptSubmitted('Keep this turn'));
    await _waitForCondition(() => generator.requests.length == 1);
    committedHandle.succeed('Committed answer');
    await _waitForState(bloc, (state) => state.messages.length == 2);

    bloc.add(const AssistantPromptSubmitted('Discard on background'));
    await _waitForCondition(() => generator.requests.length == 2);
    activeHandle.emit('Draft');
    await _waitForState(bloc, (state) => state.draftResponse == 'Draft');

    bloc.add(const AssistantSuspended());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == AssistantModelStatus.suspended,
    );
    await _waitForCondition(() => store.suspendCalls == 1);

    expect(activeHandle.cancelCalls, 1);
    expect(bloc.state.messages, hasLength(2));
    expect(bloc.state.draftPrompt, isEmpty);
    expect(bloc.state.draftResponse, isEmpty);

    bloc.add(const AssistantResumed());
    await _waitForReady(bloc);
    expect(store.prepareCalls, 2);
    expect(bloc.state.messages, hasLength(2));

    await bloc.close();
    await store.close();
  });

  test('serializes rapid lifecycle intents while native unload is pending', () async {
    final firstSuspendGate = Completer<void>();
    late final FakeAssistantModelStore store;
    store = FakeAssistantModelStore(
      onSuspend: () async {
        if (store.suspendCalls == 1) await firstSuspendGate.future;
      },
    );
    final bloc = _createBloc(store, FakeCommentGenerator())..add(const AssistantStarted());
    await _waitForReady(bloc);

    bloc.add(const AssistantSuspended());
    await _waitForCondition(() => store.suspendCalls == 1);
    bloc
      ..add(const AssistantResumed())
      ..add(const AssistantSuspended());

    firstSuspendGate.complete();
    await _waitForCondition(() => store.suspendCalls == 2);
    await _waitForState(
      bloc,
      (state) => state.modelStatus == AssistantModelStatus.suspended,
    );

    expect(store.prepareCalls, 2);
    expect(store.suspendCalls, 2);
    expect(bloc.state.modelStatus, AssistantModelStatus.suspended);

    await bloc.close();
    await store.close();
  });

  test('resume does not prepare a session that was never started', () async {
    final store = FakeAssistantModelStore();
    final bloc = _createBloc(store, FakeCommentGenerator())
      ..add(const AssistantSuspended())
      ..add(const AssistantResumed());
    await pumpEventQueue();

    expect(store.prepareCalls, 0);
    expect(store.suspendCalls, 0);
    expect(bloc.state.started, isFalse);

    await bloc.close();
    await store.close();
  });

  test('concurrent close calls cancel once without closing app-owned ports', () async {
    final store = FakeAssistantModelStore();
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle();
    generator.enqueueHandle(handle);
    final bloc = _createBloc(store, generator)..add(const AssistantStarted());
    await _waitForReady(bloc);
    bloc.add(const AssistantPromptSubmitted('Close this run'));
    await _waitForCondition(() => generator.requests.length == 1);

    await Future.wait<void>([bloc.close(), bloc.close()]);

    expect(handle.cancelCalls, 1);
    expect(store.closeCalls, 0);
    expect(generator.closeCalls, 0);
    store.emit(
      ModelStoreState.failure(
        const UnexpectedFailure(code: 'late_store_event'),
      ),
    );
    await store.close();
  });

  testWidgets('close settles after construction in the widget fake-async zone', (
    tester,
  ) async {
    final store = FakeAssistantModelStore();
    final bloc = _createBloc(store, FakeCommentGenerator());

    await tester.runAsync(
      () => bloc.close().timeout(const Duration(seconds: 2)),
    );

    expect(bloc.isClosed, isTrue);
    expect(store.closeCalls, 0);
    await store.close();
  });

  testWidgets('idle generation runner closes in the widget fake-async zone', (
    tester,
  ) async {
    final runner = AssistantGenerationRunner(
      commentGenerator: FakeCommentGenerator(),
      onUpdate: (_) {},
    );

    await tester.runAsync(
      () => runner.close().timeout(const Duration(seconds: 2)),
    );
  });

  testWidgets('generation runner drains chunks in the widget fake-async zone', (
    tester,
  ) async {
    final generator = FakeCommentGenerator();
    final handle = FakeGenerationHandle(syncChunks: true);
    generator.enqueueHandle(handle);
    final updates = <AssistantGenerationUpdate>[];
    final runner = AssistantGenerationRunner(
      commentGenerator: generator,
      onUpdate: updates.add,
    );
    final request = QwenPromptBuilder(
      systemPrompt: 'Test.',
      manualOptions: _testManualOptions,
      shortCommentOptions: _testShortCommentOptions,
    ).manualDialogue(prompt: 'Hello');

    runner.start(request);
    await tester.pump();
    await tester.runAsync(() async {
      handle
        ..emit('Answer')
        ..succeed('Answer');
      await Future<void>.delayed(Duration.zero);
    });
    for (var pump = 0; pump < 10; pump += 1) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(handle.chunksClosed, isTrue);
    expect(updates.whereType<AssistantGenerationChunk>(), hasLength(1));
    expect(updates.whereType<AssistantGenerationCompleted>(), hasLength(1));
    await tester.runAsync(runner.close);
  });
}

AssistantBloc _createBloc(
  FakeAssistantModelStore store,
  FakeCommentGenerator generator,
) {
  return AssistantBloc(
    modelStore: store,
    commentGenerator: generator,
    promptBuilder: QwenPromptBuilder(
      systemPrompt: 'You are a concise local assistant.',
      manualOptions: _testManualOptions,
      shortCommentOptions: _testShortCommentOptions,
    ),
  );
}

Future<AssistantState> _waitForReady(AssistantBloc bloc) {
  return _waitForState(
    bloc,
    (state) => state.modelStatus == AssistantModelStatus.ready,
  );
}

Future<AssistantState> _waitForState(
  AssistantBloc bloc,
  bool Function(AssistantState state) predicate,
) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate);
}

Future<void> _waitForCondition(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw TestFailure('Condition did not become true.');
}
