import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

import '../test/support/assistant_acceptance_durations.dart';

const _runNativeAssistantTest = bool.fromEnvironment(
  'RUN_NATIVE_ASSISTANT_TEST',
);
const Duration _modelPreparationTimeout = AssistantAcceptanceDurations.modelPreparation;
const Duration _generationTimeout = AssistantAcceptanceDurations.generation;
const Duration _stateTransitionTimeout = AssistantAcceptanceDurations.stateTransition;
const Duration _modelResumeTimeout = AssistantAcceptanceDurations.modelReload;
const Duration _runtimeStartTimeout = AssistantAcceptanceDurations.runtimeStart;
const Duration _runtimeCloseTimeout = AssistantAcceptanceDurations.runtimeClose;
const Duration _dependencyResetTimeout = AssistantAcceptanceDurations.dependencyReset;
const Duration _recordedYoloPollInterval = AssistantAcceptanceDurations.poll;
const Duration _fullScenarioTimeout = AssistantAcceptanceDurations.smokeScenario;
const Duration _offlineScenarioTimeout = AssistantAcceptanceDurations.offlineScenario;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offlineGuard = _OfflineGuardDownloader();

  testWidgets(
    'verified Qwen runtime streams, cancels, unloads, and reloads',
    (tester) async {
      final runtime = configureDependenciesForTesting(
        modelArtifactDownloader: offlineGuard,
      );
      final generator = runtime.commentGenerator as LlamaCommentGenerator;
      final semantics = tester.ensureSemantics();
      StreamSubscription<ObserverState>? stateSubscription;
      try {
        await runtime.start().timeout(_runtimeStartTimeout);
        await tester.pumpWidget(const PovAgentApp());
        await _pumpUntilFound(
          tester,
          find.bySemanticsLabel('Disable camera'),
        );
        final personDetection = find.semantics.byLabel(RegExp(r'^person \d+%$'));
        await _pumpUntilFound(tester, personDetection);

        // Start preparation while the recorded camera and real YOLO surface
        // remain active. The router's later duplicate start is intentionally
        // ignored by the Bloc.
        runtime.observerBloc.add(const ObserverStarted());
        await tester.pump();

        final readyState = await _waitForState(
          runtime.observerBloc,
          (state) => state.modelStatus == ObserverModelStatus.ready || state.modelStatus == ObserverModelStatus.failure,
          timeout: _modelPreparationTimeout,
        );
        if (readyState.modelStatus == ObserverModelStatus.failure) {
          fail(
            'Qwen preparation failed: '
            '${_failureDescription(readyState.modelFailure)}.',
          );
        }
        final downloadCallsAtReady = offlineGuard.downloadCalls;
        offlineGuard.rejectDownloads = true;
        await tester.pump();
        expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
        expect(personDetection, findsAtLeast(1));

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();

        var observedVisibleStreaming = false;
        stateSubscription = runtime.observerBloc.stream.listen((state) {
          if (state.activeGeneration == ObserverGenerationKind.manual && state.manualDraftResponse.isNotEmpty) {
            observedVisibleStreaming = true;
          }
        });
        await tester.enterText(
          find.byKey(assistantPromptFieldKey),
          'Reply with one short English sentence confirming that the '
          'on-device runtime is ready.',
        );
        await tester.pump();
        await tester.tap(find.byKey(assistantSubmitControlKey));
        await tester.pump();

        final completedState = await _waitForState(
          runtime.observerBloc,
          (state) => state.manualFailure != null || state.messages.length >= 2,
          timeout: _generationTimeout,
        );
        if (completedState.manualFailure != null) {
          fail(
            'Qwen generation failed: '
            '${_failureDescription(completedState.manualFailure)}.',
          );
        }
        final answer = completedState.messages.last;
        expect(answer.role, ConversationRole.assistant);
        expect(answer.content.trim(), isNotEmpty);
        expect(answer.content, isNot(contains('<think>')));
        expect(answer.content, isNot(contains('</think>')));
        expect(answer.content, matches(RegExp('[A-Za-z]')));
        expect(observedVisibleStreaming, isTrue);
        await tester.pumpAndSettle();

        final committedMessageCount = completedState.messages.length;
        await tester.enterText(
          find.byKey(assistantPromptFieldKey),
          'Write a detailed explanation of how an on-device language model '
          'works.',
        );
        await tester.pump();
        await tester.tap(find.byKey(assistantSubmitControlKey));
        await tester.pump();
        await _waitForState(
          runtime.observerBloc,
          (state) => state.activeGeneration == ObserverGenerationKind.manual,
          timeout: _stateTransitionTimeout,
        );
        await tester.pump();
        await tester.tap(find.byKey(assistantSubmitControlKey));
        await tester.pump();

        final cancelledState = await _waitForState(
          runtime.observerBloc,
          (state) => state.activeGeneration != ObserverGenerationKind.manual && state.manualDraftPrompt.isEmpty,
          timeout: _stateTransitionTimeout,
        );
        expect(cancelledState.messages, hasLength(committedMessageCount));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.hidden,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        await tester.pump();
        await _waitForState(
          runtime.observerBloc,
          (state) => state.modelStatus == ObserverModelStatus.suspended,
          timeout: _stateTransitionTimeout,
        );
        await _waitForSuccessfulUnload(
          generator,
          timeout: _stateTransitionTimeout,
        );
        expect(generator.loadedModelUsesGpu, isNull);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.hidden,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        final resumedState = await _waitForState(
          runtime.observerBloc,
          (state) => state.modelStatus == ObserverModelStatus.ready || state.modelStatus == ObserverModelStatus.failure,
          timeout: _modelResumeTimeout,
        );
        expect(resumedState.modelStatus, ObserverModelStatus.ready);
        expect(resumedState.messages, hasLength(committedMessageCount));
        expect(offlineGuard.downloadCalls, downloadCallsAtReady);
      } finally {
        await stateSubscription?.cancel();
        semantics.dispose();
        await _disposeRuntime(tester, runtime);
      }
    },
    skip: !_runNativeAssistantTest,
    timeout: const Timeout(_fullScenarioTimeout),
  );

  testWidgets(
    'verified cache restarts with network transport disabled',
    (tester) async {
      offlineGuard.rejectDownloads = true;
      final downloadCallsBeforeRestart = offlineGuard.downloadCalls;
      final runtime = configureDependenciesForTesting(
        modelArtifactDownloader: offlineGuard,
      );
      try {
        await runtime.start().timeout(_runtimeStartTimeout);
        await tester.pumpWidget(const PovAgentApp());
        runtime.observerBloc.add(const ObserverStarted());
        await tester.pump();

        final readyState = await _waitForState(
          runtime.observerBloc,
          (state) => state.modelStatus == ObserverModelStatus.ready || state.modelStatus == ObserverModelStatus.failure,
          timeout: _modelResumeTimeout,
        );
        if (readyState.modelStatus == ObserverModelStatus.failure) {
          fail(
            'Verified cache restart failed: '
            '${_failureDescription(readyState.modelFailure)}.',
          );
        }
        expect(offlineGuard.downloadCalls, downloadCallsBeforeRestart);

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(assistantPromptFieldKey),
          'Reply with one short English sentence confirming offline restart.',
        );
        await tester.pump();
        await tester.tap(find.byKey(assistantSubmitControlKey));
        await tester.pump();

        final completedState = await _waitForState(
          runtime.observerBloc,
          (state) => state.manualFailure != null || state.messages.length >= 2,
          timeout: _generationTimeout,
        );
        if (completedState.manualFailure != null) {
          fail(
            'Offline generation failed: '
            '${_failureDescription(completedState.manualFailure)}.',
          );
        }
        expect(completedState.messages.last.content.trim(), isNotEmpty);
        expect(offlineGuard.downloadCalls, downloadCallsBeforeRestart);
      } finally {
        await _disposeRuntime(tester, runtime);
      }
    },
    skip: !_runNativeAssistantTest,
    timeout: const Timeout(_offlineScenarioTimeout),
  );
}

String _failureDescription(Object? failure) {
  if (failure is! AppFailure) return 'unknown';
  final message = failure.message;
  return message == null || message.isEmpty ? failure.code : '${failure.code}: $message';
}

Future<void> _pumpUntilFound<CandidateType>(
  WidgetTester tester,
  FinderBase<CandidateType> finder,
) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    await tester.pump(_recordedYoloPollInterval);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for active recorded YOLO inference.');
}

Future<ObserverState> _waitForState(
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
}

Future<void> _waitForSuccessfulUnload(
  LlamaCommentGenerator generator, {
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    switch (generator.lastUnloadSucceeded) {
      case true:
        return;
      case false:
        fail('The native assistant model failed to unload.');
      case null:
        await Future<void>.delayed(_recordedYoloPollInterval);
    }
  }
  fail('Timed out waiting for the native assistant model to unload.');
}

Future<void> _disposeRuntime(
  WidgetTester tester,
  AppRuntime runtime,
) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> attempt(
    Future<void> Function() operation,
    Duration timeout,
  ) async {
    try {
      await operation().timeout(timeout);
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  await attempt(
    () async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    _dependencyResetTimeout,
  );
  await attempt(runtime.close, _runtimeCloseTimeout);
  await attempt(
    () => appDependencies.reset(dispose: false),
    _dependencyResetTimeout,
  );

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

final class _OfflineGuardDownloader implements ModelArtifactDownloader {
  final HttpModelArtifactDownloader _delegate = HttpModelArtifactDownloader();

  bool rejectDownloads = false;
  int downloadCalls = 0;

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) {
    downloadCalls += 1;
    if (rejectDownloads) {
      throw const _OfflineTransportException();
    }
    return _delegate.download(
      source: source,
      destinationPath: destinationPath,
      expectedBytes: expectedBytes,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }
}

final class _OfflineTransportException implements Exception {
  const _OfflineTransportException();
}
