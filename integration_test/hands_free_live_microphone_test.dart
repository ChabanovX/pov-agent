import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/domain/entities/conversation_message.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';

import '../test/support/assistant_acceptance_durations.dart';

const _runLiveMicrophoneTest = bool.fromEnvironment(
  'RUN_HANDS_FREE_LIVE_MICROPHONE_TEST',
);

/// Physical-device gate. After the READY marker, say:
/// “Assistant, what can you see in front of the camera?”
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live iPhone microphone completes one hands-free native turn',
    (tester) async {
      if (!Platform.isIOS) {
        fail('Live microphone acceptance is restricted to a physical iPhone.');
      }
      if (CompilationConstants.usesRecordedAudio) {
        fail('Live microphone acceptance requires USE_RECORDED_AUDIO=false.');
      }

      await appDependencies.reset(dispose: false);
      final runtime = configureDependencies();
      final piper = appDependencies<PiperSpeechSynthesizer>();
      final phases = <VoiceAgentPhase>[];
      final phaseSubscription = runtime.observerBloc.stream.listen((state) {
        if (phases.lastOrNull != state.voicePhase) {
          phases.add(state.voicePhase);
        }
      });

      Object? scenarioError;
      StackTrace? scenarioStackTrace;
      try {
        await runtime.start().timeout(
          AssistantAcceptanceDurations.runtimeStart,
        );
        runtime.observerBloc.add(const ObservationStopped());
        await _waitForState(
          runtime.observerBloc,
          (state) => !state.observationEnabled,
          timeout: AssistantAcceptanceDurations.stateTransition,
        );
        await tester.pumpWidget(const PovAgentApp());

        final armed = await _waitForState(
          runtime.observerBloc,
          (state) =>
              state.modelFailure != null ||
              state.asrModelFailure != null ||
              state.voiceFailure != null ||
              state.voicePhase == VoiceAgentPhase.watching,
          timeout: AssistantAcceptanceDurations.modelPreparation,
        );
        _failForTerminalState(armed, stage: 'arming live microphone');
        tester.printToConsole(
          'HANDS_FREE_LIVE_READY say="Assistant, what can you see in front '
          'of the camera?"',
        );

        final terminal = await _pumpUntilState(
          tester,
          runtime.observerBloc,
          (state) =>
              state.voiceFailure != null ||
              (state.messages.length >= 2 && state.voicePhase == VoiceAgentPhase.watching && !state.isSpeaking),
          timeout: AssistantAcceptanceDurations.liveQuestion,
        );
        _failForTerminalState(terminal, stage: 'live voice turn');

        final question = terminal.messages[terminal.messages.length - 2];
        final answer = terminal.messages.last;
        expect(question.role, ConversationRole.user);
        expect(answer.role, ConversationRole.assistant);
        expect(question.content.trim(), isNotEmpty);
        expect(answer.content.trim(), isNotEmpty);
        expect(terminal.scene.objects, isNotEmpty);
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
        expect(piper.completedPlaybacks, greaterThanOrEqualTo(1));
        tester.printToConsole(
          'HANDS_FREE_LIVE_ACCEPTANCE question=${question.content} '
          'answer_chars=${answer.content.length} '
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
        await _disposeRuntime(tester, runtime);
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }

      final primaryError = scenarioError;
      if (primaryError != null) {
        if (cleanupError case final secondaryError?) {
          Error.throwWithStackTrace(
            _LiveScenarioAndCleanupFailure(primaryError, secondaryError),
            scenarioStackTrace!,
          );
        }
        Error.throwWithStackTrace(primaryError, scenarioStackTrace!);
      }
      if (cleanupError case final error?) {
        Error.throwWithStackTrace(error, cleanupStackTrace!);
      }
    },
    skip: !_runLiveMicrophoneTest,
    timeout: const Timeout(AssistantAcceptanceDurations.observerLiveSmokeScenario),
  );
}

void _failForTerminalState(ObserverState state, {required String stage}) {
  final failure = state.modelFailure ?? state.asrModelFailure ?? state.voiceFailure;
  if (failure == null) return;
  final message = failure.message;
  final diagnostic = message == null || message.isEmpty ? failure.code : '${failure.code}: $message';
  fail('Hands-free $stage failed: $diagnostic.');
}

Future<ObserverState> _waitForState(
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
}

Future<ObserverState> _pumpUntilState(
  WidgetTester tester,
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) async {
  final elapsed = Stopwatch()..start();
  while (!predicate(bloc.state) && elapsed.elapsed < timeout) {
    await tester.pump(AssistantAcceptanceDurations.poll);
  }
  elapsed.stop();
  if (predicate(bloc.state)) return bloc.state;
  throw TimeoutException('Timed out waiting for the live voice turn.', timeout);
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

final class _LiveScenarioAndCleanupFailure implements Exception {
  const _LiveScenarioAndCleanupFailure(
    this.scenarioError,
    this.cleanupError,
  );

  final Object scenarioError;
  final Object cleanupError;

  @override
  String toString() {
    return 'Live hands-free acceptance failed: $scenarioError; cleanup also '
        'failed: $cleanupError';
  }
}
