import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';

const _runNativeAssistantTest = bool.fromEnvironment(
  'RUN_NATIVE_ASSISTANT_TEST',
);
final Duration _modelPreparationTimeout = AppAnimations.regular.slow * 2500;
final Duration _generationTimeout = AppAnimations.regular.slow * 1667;
final Duration _stateTransitionTimeout = AppAnimations.regular.slow * 84;
final Duration _modelResumeTimeout = AppAnimations.regular.slow * 834;
final Duration _fullScenarioTimeout = AppAnimations.regular.slow * 6667;
final Duration _offlineScenarioTimeout = AppAnimations.regular.slow * 3334;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offlineGuard = _OfflineGuardDownloader();

  testWidgets(
    'verified Qwen runtime streams, cancels, unloads, and reloads',
    (tester) async {
      final runtime = configureDependenciesForTesting(
        modelArtifactDownloader: offlineGuard,
      );
      final semantics = tester.ensureSemantics();
      await runtime.start();
      StreamSubscription<AssistantState>? stateSubscription;
      try {
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
        runtime.assistantBloc.add(const AssistantStarted());
        await tester.pump();

        final readyState = await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) =>
                state.modelStatus == AssistantModelStatus.ready || state.modelStatus == AssistantModelStatus.failure,
            timeout: _modelPreparationTimeout,
          ),
        );
        if (readyState == null) fail('The model readiness wait returned null.');
        if (readyState.modelStatus == AssistantModelStatus.failure) {
          fail(
            'Qwen preparation failed: '
            '${readyState.modelFailure?.code ?? 'unknown'}.',
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
        stateSubscription = runtime.assistantBloc.stream.listen((state) {
          if (state.generationStatus == AssistantGenerationStatus.generating && state.draftResponse.isNotEmpty) {
            observedVisibleStreaming = true;
          }
        });
        await tester.enterText(
          find.byKey(assistantPromptFieldKey),
          'Reply with one short English sentence confirming that the iOS '
          'Simulator is ready.',
        );
        await tester.pump();
        await tester.tap(find.byKey(assistantSubmitControlKey));
        await tester.pump();

        final completedState = await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) =>
                state.generationStatus == AssistantGenerationStatus.failure ||
                (state.generationStatus == AssistantGenerationStatus.idle && state.messages.length >= 2),
            timeout: _generationTimeout,
          ),
        );
        if (completedState == null) {
          fail('The generation completion wait returned null.');
        }
        if (completedState.generationStatus == AssistantGenerationStatus.failure) {
          fail(
            'Qwen generation failed: '
            '${completedState.generationFailure?.code ?? 'unknown'}.',
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
        await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) => state.generationStatus == AssistantGenerationStatus.generating,
            timeout: _stateTransitionTimeout,
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(assistantSubmitControlKey));
        await tester.pump();

        final cancelledState = await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) => state.generationStatus == AssistantGenerationStatus.idle && state.draftPrompt.isEmpty,
            timeout: _stateTransitionTimeout,
          ),
        );
        expect(cancelledState?.messages, hasLength(committedMessageCount));

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
        await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) => state.modelStatus == AssistantModelStatus.suspended,
            timeout: _stateTransitionTimeout,
          ),
        );

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
        final resumedState = await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) =>
                state.modelStatus == AssistantModelStatus.ready || state.modelStatus == AssistantModelStatus.failure,
            timeout: _modelResumeTimeout,
          ),
        );
        expect(resumedState?.modelStatus, AssistantModelStatus.ready);
        expect(resumedState?.messages, hasLength(committedMessageCount));
        expect(offlineGuard.downloadCalls, downloadCallsAtReady);
      } finally {
        await stateSubscription?.cancel();
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(runtime.close);
        await appDependencies.reset(dispose: false);
      }
    },
    skip: !_runNativeAssistantTest,
    timeout: Timeout(_fullScenarioTimeout),
  );

  testWidgets(
    'verified cache restarts with network transport disabled',
    (tester) async {
      offlineGuard.rejectDownloads = true;
      final downloadCallsBeforeRestart = offlineGuard.downloadCalls;
      final runtime = configureDependenciesForTesting(
        modelArtifactDownloader: offlineGuard,
      );
      await runtime.start();
      try {
        await tester.pumpWidget(const PovAgentApp());
        runtime.assistantBloc.add(const AssistantStarted());
        await tester.pump();

        final readyState = await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) =>
                state.modelStatus == AssistantModelStatus.ready || state.modelStatus == AssistantModelStatus.failure,
            timeout: _modelResumeTimeout,
          ),
        );
        if (readyState == null) fail('The offline readiness wait returned null.');
        if (readyState.modelStatus == AssistantModelStatus.failure) {
          fail(
            'Verified cache restart failed: '
            '${readyState.modelFailure?.code ?? 'unknown'}.',
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

        final completedState = await tester.runAsync(
          () => _waitForState(
            runtime.assistantBloc,
            (state) =>
                state.generationStatus == AssistantGenerationStatus.failure ||
                (state.generationStatus == AssistantGenerationStatus.idle && state.messages.length >= 2),
            timeout: _generationTimeout,
          ),
        );
        if (completedState == null) {
          fail('The offline generation wait returned null.');
        }
        if (completedState.generationStatus == AssistantGenerationStatus.failure) {
          fail(
            'Offline generation failed: '
            '${completedState.generationFailure?.code ?? 'unknown'}.',
          );
        }
        expect(completedState.messages.last.content.trim(), isNotEmpty);
        expect(offlineGuard.downloadCalls, downloadCallsBeforeRestart);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(runtime.close);
        await appDependencies.reset(dispose: false);
      }
    },
    skip: !_runNativeAssistantTest,
    timeout: Timeout(_offlineScenarioTimeout),
  );
}

Future<void> _pumpUntilFound<CandidateType>(
  WidgetTester tester,
  FinderBase<CandidateType> finder,
) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    await tester.pump(AppAnimations.regular.fast);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for active recorded YOLO inference.');
}

Future<AssistantState> _waitForState(
  AssistantBloc bloc,
  bool Function(AssistantState state) predicate, {
  required Duration timeout,
}) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
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
