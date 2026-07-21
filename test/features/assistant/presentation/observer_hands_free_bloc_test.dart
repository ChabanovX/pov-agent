import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/tracked_object.dart';

import '../../../support/fake_assistant_runtime.dart';

const _manualOptions = GenerationOptions(
  maxTokens: 32,
  temperature: 0.5,
  topP: 0.9,
  topK: 10,
  minP: 0,
);
const _shortOptions = GenerationOptions(
  maxTokens: 16,
  temperature: 0.4,
  topP: 0.8,
  topK: 8,
  minP: 0,
);

// Scenario matrix:
// - The live turn traverses wake, listening, scene-aware Qwen, and speech once.
// - A wake preempts periodic work rather than racing the single Qwen slot.
// - Permission and empty-turn failures stay recoverable through one retry.
// - Disabling releases ASR ownership and a later enable starts a fresh epoch.
// - Inactive Settings changes reconcile ready and suspended ASR snapshots.
// - Lifecycle teardown rejects callbacks from the superseded microphone handle.
void main() {
  test('only actionable microphone denials expose application settings', () {
    final denied = ObserverState(
      wakePhrase: 'assistant',
      voiceFailure: const PermissionDeniedFailure(
        code: 'microphone_permission_denied',
      ),
    );
    final permanentlyDenied = ObserverState(
      wakePhrase: 'assistant',
      voiceFailure: const PermissionDeniedFailure(
        code: 'microphone_permission_permanently_denied',
      ),
    );
    final restricted = ObserverState(
      wakePhrase: 'assistant',
      voiceFailure: const PermissionDeniedFailure(
        code: 'microphone_permission_restricted',
      ),
    );

    expect(denied.hasMicrophonePermissionFailure, isTrue);
    expect(denied.canOpenMicrophoneSettings, isTrue);
    expect(permanentlyDenied.canOpenMicrophoneSettings, isTrue);
    expect(restricted.hasMicrophonePermissionFailure, isTrue);
    expect(restricted.canOpenMicrophoneSettings, isFalse);
  });

  test('hands-free stays cold until the session switch is enabled', () async {
    final fixture = await _HandsFreeFixture.start(
      handsFreeInitiallyEnabled: false,
    );

    expect(fixture.bloc.state.handsFreeEnabled, isFalse);
    expect(fixture.bloc.state.voicePhase, VoiceAgentPhase.unavailable);
    expect(fixture.asrStore.prepareCalls, 0);
    expect(fixture.permission.requestCalls, 0);
    expect(fixture.recognizer.loadCalls, 0);

    fixture.bloc.add(
      const ObserverHandsFreeEnabledChanged(enabled: true),
    );
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );

    expect(fixture.asrStore.prepareCalls, 1);
    expect(fixture.permission.requestCalls, 1);
    expect(fixture.recognizer.loadCalls, 1);
    expect(fixture.recognizer.startCalls, 1);

    await fixture.close();
  });

  test(
    'disabling hands-free releases ASR and re-enables with a fresh input epoch',
    () async {
      final fixture = await _HandsFreeFixture.start();
      final staleHandle = fixture.recognizer.activeHandle!;
      final prepareCallsBeforeDisable = fixture.asrStore.prepareCalls;
      final permissionCallsBeforeDisable = fixture.permission.requestCalls;
      final loadCallsBeforeDisable = fixture.recognizer.loadCalls;
      final startCallsBeforeDisable = fixture.recognizer.startCalls;

      fixture.bloc.add(
        const ObserverHandsFreeEnabledChanged(enabled: false),
      );
      final disabled = await _waitForState(
        fixture.bloc,
        (state) => !state.handsFreeEnabled && state.asrModelStatus == ObserverModelStatus.suspended,
      );

      expect(disabled.voicePhase, VoiceAgentPhase.unavailable);
      expect(staleHandle.stopCalls, 1);
      expect(fixture.asrStore.suspendCalls, 1);
      expect(fixture.recognizer.unloadCalls, 1);
      expect(fixture.recognizer.activeHandle, isNull);

      staleHandle.emit(
        const SpeechRecognitionEndpoint(
          segmentId: 0,
          revision: 1,
          transcript: 'Assistant stale question',
          reason: SpeechRecognitionEndpointReason.trailingSilence,
        ),
      );
      await _flushEvents();
      expect(fixture.generator.requests, isEmpty);

      fixture.bloc.add(
        const ObserverHandsFreeEnabledChanged(enabled: true),
      );
      final watching = await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.watching,
      );
      final freshHandle = fixture.recognizer.activeHandle!;

      expect(watching.handsFreeEnabled, isTrue);
      expect(watching.asrModelStatus, ObserverModelStatus.ready);
      expect(watching.voiceFailure, isNull);
      expect(freshHandle, isNot(same(staleHandle)));
      expect(fixture.asrStore.prepareCalls, prepareCallsBeforeDisable + 1);
      expect(
        fixture.permission.requestCalls,
        permissionCallsBeforeDisable + 1,
      );
      expect(fixture.recognizer.loadCalls, loadCallsBeforeDisable + 1);
      expect(fixture.recognizer.startCalls, startCallsBeforeDisable + 1);

      staleHandle.emit(
        const SpeechRecognitionEndpoint(
          segmentId: 0,
          revision: 2,
          transcript: 'Assistant still stale',
          reason: SpeechRecognitionEndpointReason.trailingSilence,
        ),
      );
      await _flushEvents();
      expect(fixture.bloc.state.voicePhase, VoiceAgentPhase.watching);
      expect(fixture.generator.requests, isEmpty);

      freshHandle.emit(
        const SpeechRecognitionHypothesis(
          segmentId: 0,
          revision: 1,
          transcript: 'Assistant what is here',
        ),
      );
      await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.listening,
      );

      await fixture.close();
    },
  );

  test(
    'inactive enable arms when a subscribed ASR store is already ready',
    () async {
      final fixture = await _HandsFreeFixture.start();
      fixture.bloc.add(
        const ObserverHandsFreeEnabledChanged(enabled: false),
      );
      await _waitForState(
        fixture.bloc,
        (state) => !state.handsFreeEnabled && state.asrModelStatus == ObserverModelStatus.suspended,
      );

      fixture.asrStore.emit(
        ModelStoreState.ready(testAsrBundle),
      );
      await _flushEvents();
      fixture.bloc.add(const ObserverForegroundDeactivated());
      await _waitForState(
        fixture.bloc,
        (state) => !state.foregroundActive,
      );

      final permissionCallsBeforeEnable = fixture.permission.requestCalls;
      fixture.bloc.add(
        const ObserverHandsFreeEnabledChanged(enabled: true),
      );
      final enabledInSettings = await _waitForState(
        fixture.bloc,
        (state) => state.handsFreeEnabled && state.voicePhase == VoiceAgentPhase.suspended,
      );
      expect(enabledInSettings.asrModelStatus, ObserverModelStatus.suspended);
      expect(fixture.permission.requestCalls, permissionCallsBeforeEnable);

      fixture.bloc.add(const ObserverResumed());
      final watching = await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.watching,
      );

      expect(watching.asrModelStatus, ObserverModelStatus.ready);
      expect(
        fixture.permission.requestCalls,
        permissionCallsBeforeEnable + 1,
      );
      await fixture.close();
    },
  );

  test('inactive enable prepares and arms a suspended ASR store', () async {
    final fixture = await _HandsFreeFixture.start(
      handsFreeInitiallyEnabled: false,
    );
    await fixture.asrStore.suspend();
    fixture.bloc.add(const ObserverForegroundDeactivated());
    await _waitForState(
      fixture.bloc,
      (state) => !state.foregroundActive,
    );

    fixture.bloc.add(
      const ObserverHandsFreeEnabledChanged(enabled: true),
    );
    await _waitForState(
      fixture.bloc,
      (state) => state.handsFreeEnabled && state.voicePhase == VoiceAgentPhase.suspended,
    );
    fixture.bloc.add(const ObserverResumed());
    final watching = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );

    expect(watching.asrModelStatus, ObserverModelStatus.ready);
    expect(fixture.asrStore.prepareCalls, 1);
    expect(fixture.permission.requestCalls, 1);
    await fixture.close();
  });

  test('microphone recovery opens platform application settings', () async {
    final permission = FakeMicrophonePermissionGateway()
      ..enqueue(
        const AppError<void>(
          PermissionDeniedFailure(code: 'microphone_permission_denied'),
        ),
      );
    final fixture = await _HandsFreeFixture.start(permission: permission);
    await _waitForState(
      fixture.bloc,
      (state) => state.canOpenMicrophoneSettings,
    );

    fixture.bloc.add(const ObserverMicrophoneSettingsRequested());
    await _waitForCondition(() => fixture.permission.openSettingsCalls == 1);

    expect(fixture.permission.openSettingsCalls, 1);
    await fixture.close();
  });

  test('restricted microphone access never opens application settings', () async {
    final permission = FakeMicrophonePermissionGateway()
      ..enqueue(
        const AppError<void>(
          PermissionDeniedFailure(code: 'microphone_permission_restricted'),
        ),
      );
    final fixture = await _HandsFreeFixture.start(permission: permission);
    await _waitForState(
      fixture.bloc,
      (state) => state.voiceFailure?.code == 'microphone_permission_restricted',
    );

    fixture.bloc.add(const ObserverMicrophoneSettingsRequested());
    await _flushEvents();

    expect(fixture.bloc.state.canOpenMicrophoneSettings, isFalse);
    expect(fixture.permission.openSettingsCalls, 0);
    await fixture.close();
  });

  test(
    'permission denial remains visible through Settings and suspension',
    () async {
      final permission = FakeMicrophonePermissionGateway()
        ..enqueue(
          const AppError<void>(
            PermissionDeniedFailure(code: 'microphone_permission_denied'),
          ),
        );
      final fixture = await _HandsFreeFixture.start(permission: permission);
      await _waitForState(
        fixture.bloc,
        (state) => state.voiceFailure?.code == 'microphone_permission_denied',
      );

      fixture.bloc.add(const ObserverForegroundDeactivated());
      final settingsState = await _waitForState(
        fixture.bloc,
        (state) => !state.foregroundActive,
      );
      expect(settingsState.voiceFailure?.code, 'microphone_permission_denied');
      expect(settingsState.canOpenMicrophoneSettings, isTrue);

      fixture.bloc.add(const ObserverSuspended());
      final suspended = await _waitForState(
        fixture.bloc,
        (state) => state.modelStatus == ObserverModelStatus.suspended,
      );
      expect(suspended.voiceFailure?.code, 'microphone_permission_denied');
      expect(suspended.canOpenMicrophoneSettings, isTrue);

      await fixture.close();
    },
  );

  test(
    'voice turn uses the latest scene and four pairs, speaks once, then rearms',
    () async {
      final fixture = await _HandsFreeFixture.start();
      final phases = <VoiceAgentPhase>[];
      final phaseSubscription = fixture.bloc.stream.listen((state) {
        if (phases.lastOrNull != state.voicePhase) phases.add(state.voicePhase);
      });

      for (var turn = 0; turn < 5; turn += 1) {
        await fixture.completeManualTurn(
          question: 'typed question $turn',
          answer: 'typed answer $turn',
        );
      }

      final recognitionStartsBeforeVoice = fixture.recognizer.startCalls;
      final recognition = fixture.recognizer.activeHandle!;
      final generation = FakeGenerationHandle();
      final speech = FakeSpeechAttempt();
      fixture.generator.enqueueHandle(generation);
      fixture.speech.enqueueAttempt(speech);

      recognition.emit(
        const SpeechRecognitionHypothesis(
          segmentId: 0,
          revision: 1,
          transcript: 'Assistant, what',
        ),
      );
      await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.listening,
      );
      recognition.emit(
        const SpeechRecognitionEndpoint(
          segmentId: 1,
          revision: 2,
          transcript: 'is beside the backpack',
          reason: SpeechRecognitionEndpointReason.trailingSilence,
        ),
      );

      final thinking = await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.thinking,
      );
      expect(thinking.voiceQuestionDraft, 'what is beside the backpack');
      expect(recognition.stopCalls, 1);
      expect(fixture.generator.requests, hasLength(6));

      final prompt = fixture.generator.requests.last.prompt;
      expect(prompt, contains('- center: backpack'));
      expect(prompt, contains('what is beside the backpack'));
      expect(prompt, isNot(contains('typed question 0')));
      for (var turn = 1; turn < 5; turn += 1) {
        expect(prompt, contains('typed question $turn'));
        expect(prompt, contains('typed answer $turn'));
      }

      generation
        ..emit('It is a water bottle.')
        ..succeed('It is a water bottle.');
      final speaking = await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.speaking,
      );
      expect(speaking.messages.last.content, 'It is a water bottle.');
      expect(fixture.speech.spokenTexts, ['It is a water bottle.']);
      expect(
        fixture.recognizer.startCalls,
        recognitionStartsBeforeVoice,
        reason: 'ASR must remain stopped throughout TTS.',
      );

      speech.succeed();
      await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.watching,
      );
      expect(
        fixture.recognizer.startCalls,
        recognitionStartsBeforeVoice + 1,
      );
      expect(
        phases,
        containsAllInOrder([
          VoiceAgentPhase.wakeDetected,
          VoiceAgentPhase.listening,
          VoiceAgentPhase.thinking,
          VoiceAgentPhase.speaking,
          VoiceAgentPhase.watching,
        ]),
      );

      await phaseSubscription.cancel();
      await fixture.close();
    },
  );

  test('wake phrase preempts an automatic generation before listening', () async {
    final fixture = await _HandsFreeFixture.start();
    final automatic = FakeGenerationHandle();
    final voice = FakeGenerationHandle();
    fixture.generator
      ..enqueueHandle(automatic)
      ..enqueueHandle(voice);

    fixture.timers.current.fire();
    await _waitForCondition(
      () => fixture.bloc.state.activeGeneration == ObserverGenerationKind.automatic,
    );

    final recognition = fixture.recognizer.activeHandle!
      ..emit(
        const SpeechRecognitionHypothesis(
          segmentId: 0,
          revision: 1,
          transcript: 'assistant explain this',
        ),
      );
    final listening = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.listening,
    );

    expect(listening.activeGeneration, isNull);
    expect(automatic.cancelCalls, 1);
    fixture.timers.current.fire();
    await _flushEvents();
    expect(
      fixture.generator.requests,
      hasLength(1),
      reason: 'Periodic work must stay blocked throughout the voice turn.',
    );
    recognition.emit(
      const SpeechRecognitionEndpoint(
        segmentId: 1,
        revision: 2,
        transcript: 'scene',
        reason: SpeechRecognitionEndpointReason.trailingSilence,
      ),
    );
    await _waitForState(
      fixture.bloc,
      (state) => state.activeGeneration == ObserverGenerationKind.voice,
    );
    expect(fixture.generator.requests, hasLength(2));

    await fixture.close();
  });

  test('a delayed ASR start stays armed across automatic failure', () async {
    final fixture = _HandsFreeFixture._();
    final startGate = Completer<AppResult<SpeechRecognitionHandle>>();
    final recognition = FakeSpeechRecognitionHandle();
    final automatic = FakeGenerationHandle();
    fixture.recognizer.onStart = () => startGate.future;
    fixture.generator.enqueueHandle(automatic);
    fixture.bloc.add(const ObserverStarted());

    await _waitForState(
      fixture.bloc,
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    await _waitForCondition(() => fixture.recognizer.startCalls == 1);
    fixture.timers.current.fire();
    await _waitForState(
      fixture.bloc,
      (state) => state.activeGeneration == ObserverGenerationKind.automatic,
    );

    startGate.complete(AppSuccess<SpeechRecognitionHandle>(recognition));
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    automatic.fail(
      const DeviceUnavailableFailure(code: 'automatic_failed'),
    );
    await _waitForState(
      fixture.bloc,
      (state) => state.automaticFailure?.code == 'automatic_failed',
    );

    expect(fixture.bloc.state.voicePhase, VoiceAgentPhase.watching);
    expect(recognition.stopCalls, 0);
    expect(fixture.recognizer.startCalls, 1);
    await fixture.close();
  });

  test('permission denial and an empty turn can each be retried', () async {
    final permission = FakeMicrophonePermissionGateway()
      ..enqueue(
        const AppError<void>(
          PermissionDeniedFailure(code: 'microphone_permission_denied'),
        ),
      );
    final fixture = await _HandsFreeFixture.start(permission: permission);

    final denied = await _waitForState(
      fixture.bloc,
      (state) => state.voiceFailure?.code == 'microphone_permission_denied',
    );
    expect(denied.voicePhase, VoiceAgentPhase.failure);
    expect(fixture.recognizer.startCalls, 0);

    fixture.bloc.add(const ObserverVoiceRetryRequested());
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    fixture.recognizer.activeHandle!.emit(
      const SpeechRecognitionEndpoint(
        segmentId: 0,
        revision: 1,
        transcript: 'Assistant',
        reason: SpeechRecognitionEndpointReason.trailingSilence,
      ),
    );
    final empty = await _waitForState(
      fixture.bloc,
      (state) => state.voiceFailure?.code == 'voice_question_empty',
    );
    expect(empty.voicePhase, VoiceAgentPhase.failure);

    fixture.bloc.add(const ObserverVoiceRetryRequested());
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    expect(fixture.recognizer.startCalls, 2);

    await fixture.close();
  });

  test('foreground lifecycle replaces the microphone handle and rejects stale input', () async {
    final fixture = await _HandsFreeFixture.start();
    final staleHandle = fixture.recognizer.activeHandle!;

    fixture.bloc.add(const ObserverForegroundDeactivated());
    await _waitForState(fixture.bloc, (state) => !state.foregroundActive);
    expect(staleHandle.stopCalls, 1);

    staleHandle.emit(
      const SpeechRecognitionEndpoint(
        segmentId: 0,
        revision: 1,
        transcript: 'Assistant stale question',
        reason: SpeechRecognitionEndpointReason.trailingSilence,
      ),
    );
    await _flushEvents();
    expect(fixture.generator.requests, isEmpty);

    fixture.bloc.add(const ObserverResumed());
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    expect(fixture.recognizer.activeHandle, isNot(same(staleHandle)));

    await fixture.close();
  });

  test('failed microphone pause exposes a retryable voice failure', () async {
    final fixture = await _HandsFreeFixture.start();
    final recognition = fixture.recognizer.activeHandle!
      ..enqueueStopResult(
        const AppError<void>(
          DeviceUnavailableFailure(code: 'microphone_stop_failed'),
        ),
      );
    final generation = FakeGenerationHandle();
    fixture.generator.enqueueHandle(generation);

    fixture.timers.current.fire();
    await _waitForState(
      fixture.bloc,
      (state) => state.activeGeneration == ObserverGenerationKind.automatic,
    );
    generation.succeed('The generated observation is still committed.');

    final failed = await _waitForState(
      fixture.bloc,
      (state) => state.voiceFailure?.code == 'microphone_stop_failed',
    );
    expect(failed.voicePhase, VoiceAgentPhase.failure);
    expect(failed.comments.single.text, 'The generated observation is still committed.');
    expect(fixture.speech.spokenTexts, isEmpty);
    expect(recognition.stopCalls, 1);

    fixture.bloc.add(const ObserverVoiceRetryRequested());
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    expect(recognition.stopCalls, 2);
    expect(fixture.recognizer.activeHandle, isNot(same(recognition)));

    await fixture.close();
  });

  test('voice retry settles retained speech cleanup before rearming ASR', () async {
    final fixture = await _HandsFreeFixture.start();
    final generation = FakeGenerationHandle();
    final speech = FakeSpeechAttempt();
    fixture.generator.enqueueHandle(generation);
    fixture.speech.enqueueAttempt(speech);

    fixture.recognizer.activeHandle!
      ..emit(
        const SpeechRecognitionHypothesis(
          segmentId: 0,
          revision: 1,
          transcript: 'Assistant what',
        ),
      )
      ..emit(
        const SpeechRecognitionEndpoint(
          segmentId: 1,
          revision: 2,
          transcript: 'is here',
          reason: SpeechRecognitionEndpointReason.trailingSilence,
        ),
      );
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.thinking,
    );
    generation.succeed('A person is here.');
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.speaking,
    );

    var stopAttempts = 0;
    fixture.speech.onStop = () async {
      stopAttempts += 1;
      if (stopAttempts == 1) {
        return const AppError<void>(
          DeviceUnavailableFailure(code: 'speech_stop_failed'),
        );
      }
      return const AppSuccess<void>(null);
    };
    speech.fail(
      const DeviceUnavailableFailure(code: 'speech_playback_failed'),
    );

    final failed = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.failure && state.activeVoiceSpeechTurnId != null,
    );
    expect(failed.isSpeaking, isTrue);
    expect(failed.speechFailure?.code, 'speech_stop_failed');

    final recognitionStartsBeforeRetry = fixture.recognizer.startCalls;
    fixture.bloc.add(const ObserverVoiceRetryRequested());
    final watching = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    expect(stopAttempts, 2);
    expect(watching.isSpeaking, isFalse);
    expect(watching.voiceFailure, isNull);
    expect(watching.speechFailure, isNull);
    expect(
      fixture.recognizer.startCalls,
      recognitionStartsBeforeRetry + 1,
    );

    await fixture.close();
  });

  test('resume restores voice-answer stop recovery after repeated failures', () async {
    final fixture = await _HandsFreeFixture.start();
    final generation = FakeGenerationHandle();
    final speech = FakeSpeechAttempt();
    fixture.generator.enqueueHandle(generation);
    fixture.speech.enqueueAttempt(speech);

    fixture.recognizer.activeHandle!
      ..emit(
        const SpeechRecognitionHypothesis(
          segmentId: 0,
          revision: 1,
          transcript: 'Assistant what',
        ),
      )
      ..emit(
        const SpeechRecognitionEndpoint(
          segmentId: 1,
          revision: 2,
          transcript: 'is here',
          reason: SpeechRecognitionEndpointReason.trailingSilence,
        ),
      );
    await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.thinking,
    );
    generation.succeed('A person is here.');
    final speaking = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.speaking,
    );
    final turnId = speaking.activeVoiceSpeechTurnId;
    expect(turnId, isNotNull);

    var stopAttempts = 0;
    fixture.speech.onStop = () async {
      stopAttempts += 1;
      if (stopAttempts < 4) {
        return const AppError<void>(
          DeviceUnavailableFailure(code: 'speech_stop_failed'),
        );
      }
      return const AppSuccess<void>(null);
    };
    fixture.bloc.add(const ObserverForegroundDeactivated());
    await _waitForState(
      fixture.bloc,
      (state) => !state.foregroundActive && state.speechFailure != null,
    );
    fixture.bloc.add(const ObserverSuspended());
    await _waitForState(
      fixture.bloc,
      (state) => state.modelStatus == ObserverModelStatus.suspended,
    );

    fixture.bloc.add(const ObserverResumed());
    final recoverable = await _waitForState(
      fixture.bloc,
      (state) =>
          state.foregroundActive &&
          state.voicePhase == VoiceAgentPhase.failure &&
          state.activeVoiceSpeechTurnId == turnId,
    );
    expect(recoverable.voiceFailure?.code, 'speech_stop_failed');
    expect(recoverable.speechFailure?.code, 'speech_stop_failed');
    expect(stopAttempts, 3);

    fixture.bloc.add(const ObserverVoiceRetryRequested());
    final watching = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    expect(stopAttempts, 4);
    expect(watching.activeVoiceSpeechTurnId, isNull);
    expect(watching.voiceFailure, isNull);
    expect(watching.speechFailure, isNull);

    await fixture.close();
  });

  test('native ASR load retry restores ready model status', () async {
    final fixture = _HandsFreeFixture._();
    fixture.recognizer.enqueueLoadResult(
      const AppError<void>(
        DeviceUnavailableFailure(code: 'asr_native_load_failed'),
      ),
    );
    fixture.bloc.add(const ObserverStarted());

    final failed = await _waitForState(
      fixture.bloc,
      (state) => state.asrModelFailure?.code == 'asr_native_load_failed',
    );
    expect(failed.asrModelStatus, ObserverModelStatus.failure);

    fixture.bloc.add(const ObserverVoiceRetryRequested());
    final watching = await _waitForState(
      fixture.bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
    expect(watching.asrModelStatus, ObserverModelStatus.ready);
    expect(watching.asrModelFailure, isNull);
    expect(fixture.recognizer.loadCalls, 2);

    await fixture.close();
  });
}

final class _HandsFreeFixture {
  _HandsFreeFixture._({
    FakeMicrophonePermissionGateway? permission,
    bool handsFreeInitiallyEnabled = true,
  }) : scene = FakeSceneSource(current: _scene()),
       qwenStore = FakeAssistantModelStore(),
       asrStore = FakeAsrModelStore(),
       generator = FakeCommentGenerator(),
       permission = permission ?? FakeMicrophonePermissionGateway(),
       recognizer = FakeSpeechRecognizer(),
       speech = FakeSpeechSynthesizer(),
       timers = _TimerHarness() {
    bloc = ObserverBloc(
      generation: ObserverGenerationDependencies(
        sceneSource: scene,
        qwenModelStore: qwenStore,
        commentGenerator: generator,
        requestBuilder: ObserverRequestBuilder(
          qwenPromptBuilder: QwenPromptBuilder(
            systemPrompt: 'You are a concise local observer.',
            dialogueOptions: _manualOptions,
            shortCommentOptions: _shortOptions,
          ),
        ),
      ),
      voice: ObserverVoiceDependencies(
        asrModelStore: asrStore,
        microphonePermissionGateway: this.permission,
        speechRecognizer: recognizer,
        speechSynthesizer: speech,
        wakePhrase: 'assistant',
        questionDeadline: testVoiceQuestionDeadline,
      ),
      handsFreeInitiallyEnabled: handsFreeInitiallyEnabled,
      periodicTimerFactory: timers.create,
    );
  }

  static Future<_HandsFreeFixture> start({
    FakeMicrophonePermissionGateway? permission,
    bool handsFreeInitiallyEnabled = true,
  }) async {
    final fixture = _HandsFreeFixture._(
      permission: permission,
      handsFreeInitiallyEnabled: handsFreeInitiallyEnabled,
    );
    fixture.bloc.add(const ObserverStarted());
    if (!handsFreeInitiallyEnabled) {
      await _waitForState(
        fixture.bloc,
        (state) => state.modelStatus == ObserverModelStatus.ready,
      );
    } else if (permission == null) {
      await _waitForState(
        fixture.bloc,
        (state) => state.voicePhase == VoiceAgentPhase.watching,
      );
    } else {
      await _waitForState(
        fixture.bloc,
        (state) => state.modelStatus == ObserverModelStatus.ready,
      );
    }
    return fixture;
  }

  final FakeSceneSource scene;
  final FakeAssistantModelStore qwenStore;
  final FakeAsrModelStore asrStore;
  final FakeCommentGenerator generator;
  final FakeMicrophonePermissionGateway permission;
  final FakeSpeechRecognizer recognizer;
  final FakeSpeechSynthesizer speech;
  final _TimerHarness timers;
  late final ObserverBloc bloc;

  Future<void> completeManualTurn({
    required String question,
    required String answer,
  }) async {
    final previousMessages = bloc.state.messages.length;
    final previousStarts = recognizer.startCalls;
    final handle = FakeGenerationHandle();
    generator.enqueueHandle(handle);
    bloc.add(ObserverPromptSubmitted(question));
    await _waitForState(
      bloc,
      (state) => state.activeGeneration == ObserverGenerationKind.manual,
    );
    handle.succeed(answer);
    await _waitForState(
      bloc,
      (state) => state.messages.length == previousMessages + 2,
    );
    await _waitForCondition(() => recognizer.startCalls == previousStarts + 1);
    await _waitForState(
      bloc,
      (state) => state.voicePhase == VoiceAgentPhase.watching,
    );
  }

  Future<void> close() async {
    await bloc.close();
    await recognizer.close();
    await speech.close();
    await generator.close();
    await asrStore.close();
    await qwenStore.close();
    await scene.close();
  }
}

SceneSnapshot _scene() {
  return SceneSnapshot(
    objects: const [
      TrackedObject(
        id: 1,
        classId: 24,
        label: 'backpack',
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
  return bloc.stream
      .firstWhere(predicate)
      .timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          final state = bloc.state;
          throw TestFailure(
            'State did not settle: model=${state.modelStatus}, '
            'voice=${state.voicePhase}, generation=${state.activeGeneration}, '
            'automaticFailure=${state.automaticFailure?.code}.',
          );
        },
      );
}

Future<void> _waitForCondition(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await _flushEvents();
  }
  fail('Expected condition to become true.');
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _TimerHarness {
  final List<_FakePeriodicTimer> created = [];

  _FakePeriodicTimer get current => created.last;

  Timer create(Duration duration, void Function() onTick) {
    final timer = _FakePeriodicTimer(onTick);
    created.add(timer);
    return timer;
  }
}

final class _FakePeriodicTimer implements Timer {
  _FakePeriodicTimer(this._onTick);

  final void Function() _onTick;
  var _active = true;
  var _tick = 0;

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
  void cancel() => _active = false;
}
