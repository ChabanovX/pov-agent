import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/data/adapters/just_audio_generated_speech_player.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_asr_model_store.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

import '../test/support/assistant_acceptance_durations.dart';

const _runNativeHandsFreeTest = bool.fromEnvironment(
  'RUN_NATIVE_HANDS_FREE_TEST',
);

// Native scenario matrix:
// - Bundled PCM crosses the real sherpa recognizer and wake/listening policy.
// - The recognized question reaches real Qwen with a live recorded-YOLO scene.
// - The committed answer crosses real Piper playback before ASR re-arms.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recorded speech drives native ASR, scene-aware Qwen, and Piper end to end',
    (tester) async {
      if (!Platform.isIOS && !Platform.isAndroid) {
        fail(
          'Hands-free native acceptance supports only iOS and Android, not '
          '${Platform.operatingSystem}.',
        );
      }
      if (!CompilationConstants.usesRecordedAudio || !CompilationConstants.usesRecordedVideo) {
        fail(
          'Native hands-free acceptance requires USE_RECORDED_AUDIO=true and '
          'USE_RECORDED_VIDEO=true.',
        );
      }

      await appDependencies.reset(dispose: false);
      final runtime = configureDependencies();
      final piper = appDependencies<PiperSpeechSynthesizer>();
      final player = appDependencies<JustAudioGeneratedSpeechPlayer>();
      final asrStore = appDependencies<VerifiedAsrModelStore>();
      final phases = <VoiceAgentPhase>[];
      final asrPhases = <ModelStorePhase>[];
      final phaseSubscription = runtime.observerBloc.stream.listen((state) {
        if (phases.lastOrNull != state.voicePhase) {
          phases.add(state.voicePhase);
        }
      });
      final asrSubscription = asrStore.states.listen(
        (state) => asrPhases.add(state.phase),
      );
      final semantics = tester.ensureSemantics();

      Object? scenarioError;
      StackTrace? scenarioStackTrace;
      try {
        await runtime.start().timeout(
          AssistantAcceptanceDurations.runtimeStart,
        );
        runtime.observerBloc.add(const ObservationStopped());
        await _waitForState(
          runtime.observerBloc,
          (state) => !state.observationEnabled && state.activeGeneration != ObserverGenerationKind.automatic,
          timeout: AssistantAcceptanceDurations.stateTransition,
        );

        await tester.pumpWidget(const PovAgentApp());
        await _pumpUntilFound(
          tester,
          find.bySemanticsLabel('Disable camera'),
        );
        final personDetection = find.semantics.byLabel(
          RegExp(r'^person \d+%$'),
        );
        await _pumpUntilFound(tester, personDetection);

        final terminal = await _waitForState(
          runtime.observerBloc,
          (state) =>
              state.modelFailure != null ||
              state.asrModelFailure != null ||
              state.voiceFailure != null ||
              state.messages.length >= 2,
          timeout: AssistantAcceptanceDurations.modelPreparation + AssistantAcceptanceDurations.generation,
        );
        _failForTerminalState(terminal);

        final settled = await _waitForState(
          runtime.observerBloc,
          (state) =>
              state.voiceFailure != null ||
              (state.messages.length >= 2 && state.voicePhase == VoiceAgentPhase.watching && !state.isSpeaking),
          timeout: AssistantAcceptanceDurations.modelPreparation,
        );
        _failForTerminalState(settled);

        expect(settled.messages, hasLength(greaterThanOrEqualTo(2)));
        final question = settled.messages[settled.messages.length - 2];
        final answer = settled.messages.last;
        expect(question.role, ConversationRole.user);
        expect(answer.role, ConversationRole.assistant);
        expect(
          _normalize(question.content),
          contains('what can you see in front of the camera'),
        );
        expect(answer.content.trim(), isNotEmpty);
        expect(answer.content, isNot(contains('<think>')));
        expect(settled.scene.objects, isNotEmpty);
        expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
        expect(personDetection, findsAtLeast(1));

        expect(
          phases,
          containsAllInOrder([
            VoiceAgentPhase.watching,
            VoiceAgentPhase.wakeDetected,
            VoiceAgentPhase.listening,
            VoiceAgentPhase.thinking,
            VoiceAgentPhase.speaking,
            VoiceAgentPhase.watching,
          ]),
        );
        expect(asrPhases, contains(ModelStorePhase.verifying));
        expect(asrPhases, contains(ModelStorePhase.ready));
        expect(piper.synthesisAttempts, greaterThanOrEqualTo(1));
        expect(piper.synthesisSettlements, piper.synthesisAttempts);
        expect(piper.completedPlaybacks, greaterThanOrEqualTo(1));
        expect(player.playbackProbe.startedCount, greaterThanOrEqualTo(1));
        expect(player.playbackProbe.completedCount, greaterThanOrEqualTo(1));
        expect(player.playbackProbe.failedCount, 0);

        await tester.tap(find.text('Assistant').last);
        await _pumpUntilFound(
          tester,
          find.byKey(handsFreeAgentPanelKey),
        );
        expect(find.byKey(handsFreeAgentPanelKey), findsOneWidget);
        expect(
          find.text('Say “Assistant” to ask about the current scene.'),
          findsOneWidget,
        );
        tester.printToConsole(
          'HANDS_FREE_NATIVE_ACCEPTANCE '
          'platform=${Platform.operatingSystem} '
          'question=${question.content} '
          'answer_chars=${answer.content.length} '
          'scene_objects=${settled.scene.objects.length} '
          'piper_playbacks=${piper.completedPlaybacks}',
        );
      } on Object catch (error, stackTrace) {
        scenarioError = error;
        scenarioStackTrace = stackTrace;
      }

      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      try {
        await phaseSubscription.cancel().timeout(
          AssistantAcceptanceDurations.subscriptionCancel,
        );
        await asrSubscription.cancel().timeout(
          AssistantAcceptanceDurations.subscriptionCancel,
        );
        semantics.dispose();
        await _disposeRuntime(tester, runtime);
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }

      final primaryError = scenarioError;
      if (primaryError != null) {
        if (cleanupError case final secondaryError?) {
          Error.throwWithStackTrace(
            _HandsFreeScenarioAndCleanupFailure(
              primaryError,
              secondaryError,
            ),
            scenarioStackTrace!,
          );
        }
        Error.throwWithStackTrace(primaryError, scenarioStackTrace!);
      }
      if (cleanupError case final error?) {
        Error.throwWithStackTrace(error, cleanupStackTrace!);
      }
    },
    skip: !_runNativeHandsFreeTest,
    timeout: const Timeout(AssistantAcceptanceDurations.hardwareScenario),
  );
}

void _failForTerminalState(ObserverState state) {
  final failure = state.modelFailure ?? state.asrModelFailure ?? state.voiceFailure;
  if (failure != null) {
    fail('Hands-free native flow failed: ${_failureDescription(failure)}.');
  }
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
}

Future<ObserverState> _waitForState(
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
}

Future<void> _pumpUntilFound<CandidateType>(
  WidgetTester tester,
  FinderBase<CandidateType> finder,
) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    await tester.pump(AssistantAcceptanceDurations.poll);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for recorded camera acceptance UI.');
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
    AssistantAcceptanceDurations.widgetDetach,
  );
  await attempt(runtime.close, AssistantAcceptanceDurations.runtimeClose);
  await attempt(
    () => appDependencies.reset(dispose: false),
    AssistantAcceptanceDurations.dependencyReset,
  );

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

String _failureDescription(AppFailure failure) {
  final message = failure.message;
  return message == null || message.isEmpty ? failure.code : '${failure.code}: $message';
}

final class _HandsFreeScenarioAndCleanupFailure implements Exception {
  const _HandsFreeScenarioAndCleanupFailure(
    this.scenarioError,
    this.cleanupError,
  );

  final Object scenarioError;
  final Object cleanupError;

  @override
  String toString() {
    return 'Hands-free acceptance failed: $scenarioError; cleanup also '
        'failed: $cleanupError';
  }
}
