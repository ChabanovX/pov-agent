import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/app/model_pack/model_pack_receipt_store.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import '../../support/fake_assistant_runtime.dart';
import '../../support/fake_camera_controller.dart';
import '../../support/test_assistant_resources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('owns camera and scene startup and shutdown exactly once', () async {
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );

    expect(controller.initCalls, 0);
    expect(controller.closeCalls, 0);

    await runtime.start();
    await runtime.start();

    expect(controller.initCalls, 1);
    expect(controller.enableCalls, hasLength(1));

    for (var frame = 0; frame < 3; frame += 1) {
      controller.emit(
        ObservationDetectionsUpdated(
          detections: const [
            Detection(
              classId: 0,
              label: 'person',
              confidence: 0.9,
              box: NormalizedBox(
                left: 0.1,
                top: 0.1,
                right: 0.3,
                bottom: 0.3,
              ),
            ),
          ],
          observedAt: DateTime.utc(2026, 7, 19, 12, 0, frame),
        ),
      );
    }
    expect(sceneSession.current.objects.single.label, 'person');

    final sceneChangesComplete = expectLater(
      sceneSession.changes,
      emitsDone,
    );

    await runtime.close();
    await runtime.close();
    await sceneChangesComplete;

    expect(controller.closeCalls, 1);
    expect(assistant.modelStore.closeCalls, 1);
    expect(assistant.asrModelStore.closeCalls, 1);
    expect(assistant.commentGenerator.closeCalls, 1);
    expect(assistant.speechRecognizer.closeCalls, 1);
    expect(assistant.speechSynthesizer.closeCalls, 1);
  });

  test(
    'runtime reconciliation preserves contextual camera activation',
    () async {
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(
          controller,
          initiallyRequestedEnabled: false,
        ),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );

      await runtime.start();
      expect(controller.initCalls, 1);
      expect(controller.enableCalls, isEmpty);
      expect(runtime.cameraBloc.state.activationRequested, isFalse);

      await runtime.setAssistantDestinationActive(active: false);
      await runtime.setAssistantDestinationActive(active: true);
      expect(controller.enableCalls, isEmpty);
      expect(runtime.cameraBloc.state.activationRequested, isFalse);

      runtime.cameraBloc.add(const CameraEnableRequested());
      await _waitForCondition(() => controller.enableCalls.isNotEmpty);
      expect(runtime.cameraBloc.state.activationRequested, isTrue);

      await runtime.close();
    },
  );

  test('settles startup when camera discovery returns no lenses', () async {
    final controller = FakeCameraController(
      capabilities: CameraCapabilities(
        availableLenses: const [],
        preferredLens: CameraLens.back,
      ),
    );
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );

    await runtime.start().timeout(const Duration(seconds: 1));

    expect(runtime.cameraBloc.state.status, CameraStatus.disabled);
    expect(controller.enableCalls, isEmpty);

    await runtime.close();
  });

  test('close before start prevents later resource acquisition', () async {
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    final sceneChangesComplete = expectLater(
      sceneSession.changes,
      emitsDone,
    );

    await runtime.close();
    await sceneChangesComplete;

    final rejectedStart = runtime.start();
    expect(identical(rejectedStart, runtime.start()), isTrue);
    await expectLater(rejectedStart, throwsStateError);
    expect(controller.initCalls, 0);
    expect(controller.closeCalls, 1);
  });

  test('close wins an immediate overlap with startup', () async {
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    final sceneChangesComplete = expectLater(
      sceneSession.changes,
      emitsDone,
    );

    final startTask = runtime.start();
    final closeTask = runtime.close();
    expect(identical(closeTask, runtime.close()), isTrue);
    await Future.wait([startTask, closeTask]);
    await sceneChangesComplete;

    expect(controller.closeCalls, 1);
    await expectLater(runtime.start(), throwsStateError);
  });

  test('close cancels startup after controller initialization begins', () async {
    final initializationStarted = Completer<void>();
    final releaseInitialization = Completer<void>();
    final controller = FakeCameraController(
      onInit: () async {
        initializationStarted.complete();
        await releaseInitialization.future;
      },
    );
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );

    final startTask = runtime.start();
    await initializationStarted.future;

    final closeTask = runtime.close();
    await startTask;
    expect(controller.closeCalls, 0);
    releaseInitialization.complete();
    await closeTask;

    expect(controller.initCalls, 1);
    expect(controller.closeCalls, 1);
  });

  test(
    'suspends and reloads the eager observer session',
    () async {
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
      );

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.paused);
      await _waitForCondition(
        () =>
            assistant.modelStore.suspendCalls == 1 &&
            controller.disableCalls == 1 &&
            assistant.observerBloc.state.modelStatus == ObserverModelStatus.suspended,
      );
      expect(assistant.modelStore.suspendCalls, 1);
      expect(controller.disableCalls, 1);

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _waitForCondition(
        () =>
            assistant.modelStore.prepareCalls == 2 &&
            controller.enableCalls.length == 2 &&
            assistant.observerBloc.state.foregroundActive,
      );

      expect(assistant.modelStore.prepareCalls, 2);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );
      expect(controller.enableCalls, hasLength(2));

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.paused);
      await _waitForCondition(
        () =>
            assistant.modelStore.suspendCalls == 2 &&
            controller.disableCalls == 2 &&
            assistant.observerBloc.state.modelStatus == ObserverModelStatus.suspended,
      );
      expect(assistant.modelStore.suspendCalls, 2);
      expect(controller.disableCalls, 2);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.suspended,
      );

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _waitForCondition(
        () =>
            assistant.modelStore.prepareCalls == 3 &&
            controller.enableCalls.length == 3 &&
            assistant.observerBloc.state.foregroundActive,
      );
      expect(assistant.modelStore.prepareCalls, 3);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );
      expect(controller.enableCalls, hasLength(3));

      await runtime.close();
    },
  );

  test(
    'settings quiesces foreground resources without suspending models',
    () async {
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
      );

      await runtime.setAssistantDestinationActive(active: false);

      expect(assistant.observerBloc.state.foregroundActive, isFalse);
      expect(runtime.cameraBloc.state.status, CameraStatus.disabled);
      expect(controller.disableCalls, 1);
      expect(assistant.modelStore.suspendCalls, 0);

      await runtime.setAssistantDestinationActive(active: true);
      await _waitForCondition(
        () => assistant.observerBloc.state.foregroundActive && runtime.cameraBloc.state.status == CameraStatus.enabled,
      );

      expect(controller.enableCalls, hasLength(2));
      expect(assistant.modelStore.prepareCalls, 1);
      expect(assistant.modelStore.suspendCalls, 0);

      await runtime.close();
    },
  );

  test('rapid Assistant return is queued behind tab quiescence', () async {
    final releaseCancellation = Completer<void>();
    final handle = FakeGenerationHandle()..onCancel = () => releaseCancellation.future;
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    assistant.commentGenerator.onGenerate = (_) async => AppSuccess(handle);
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    await runtime.start();
    await _waitForCondition(
      () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
    );
    assistant.observerBloc.add(
      const ObserverPromptSubmitted('Describe the scene'),
    );
    await _waitForCondition(
      () => assistant.observerBloc.state.activeGeneration == ObserverGenerationKind.manual,
    );

    final deactivateTask = runtime.setAssistantDestinationActive(active: false);
    await _waitForCondition(() => handle.cancelCalls == 1);
    var deactivationCompleted = false;
    unawaited(deactivateTask.then((_) => deactivationCompleted = true));
    final reactivateTask = runtime.setAssistantDestinationActive(active: true);
    await _waitForCondition(() => controller.disableCalls == 1);

    expect(deactivationCompleted, isFalse);
    expect(controller.enableCalls, hasLength(1));

    releaseCancellation.complete();
    await Future.wait([deactivateTask, reactivateTask]);
    await _waitForCondition(
      () => assistant.observerBloc.state.foregroundActive,
    );

    expect(assistant.observerBloc.state.activeGeneration, isNull);
    expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
    expect(controller.disableCalls, 1);
    expect(controller.enableCalls, hasLength(2));
    expect(assistant.modelStore.suspendCalls, 0);

    await runtime.close();
  });

  test('privacy cover remains visible until the camera resumes', () async {
    final secondEnableStarted = Completer<void>();
    final releaseSecondEnable = Completer<void>();
    var enableCall = 0;
    final controller = FakeCameraController(
      onEnable: (_) async {
        enableCall += 1;
        if (enableCall != 2) return;
        secondEnableStarted.complete();
        await releaseSecondEnable.future;
      },
    );
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    await runtime.start();
    await _waitForCondition(
      () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
    );

    expect(runtime.privacyCoverVisible.value, isFalse);
    runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(runtime.privacyCoverVisible.value, isTrue);
    await _waitForCondition(
      () => controller.disableCalls == 1 && assistant.modelStore.suspendCalls == 1,
    );

    runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await secondEnableStarted.future;
    expect(runtime.privacyCoverVisible.value, isTrue);

    releaseSecondEnable.complete();
    await _waitForCondition(
      () => !runtime.privacyCoverVisible.value,
    );
    expect(runtime.cameraBloc.state.status, CameraStatus.enabled);

    await runtime.close();
  });

  test(
    'deactivates the camera while slow generation cancellation settles',
    () async {
      final releaseCancellation = Completer<void>();
      final cameraDeactivationStarted = Completer<void>();
      final handle = FakeGenerationHandle()..onCancel = () => releaseCancellation.future;
      final controller = FakeCameraController(
        onDisable: () async {
          cameraDeactivationStarted.complete();
        },
      );
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      assistant.commentGenerator.onGenerate = (_) async => AppSuccess(handle);
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
      );
      assistant.observerBloc.add(
        const ObserverPromptSubmitted('Describe the scene'),
      );
      await _waitForCondition(
        () => assistant.observerBloc.state.activeGeneration == ObserverGenerationKind.manual,
      );
      expect(
        assistant.observerBloc.state.activeGeneration,
        ObserverGenerationKind.manual,
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await _waitForCondition(
        () => handle.cancelCalls == 1 && controller.disableCalls == 1,
      );

      expect(handle.cancelCalls, 1);
      expect(controller.disableCalls, 1);
      expect(cameraDeactivationStarted.isCompleted, isTrue);
      expect(assistant.observerBloc.state.foregroundActive, isTrue);
      expect(
        assistant.observerBloc.state.activeGeneration,
        ObserverGenerationKind.manual,
      );
      releaseCancellation.complete();
      await handle.cancel();
      await _waitForCondition(
        () =>
            !assistant.observerBloc.state.foregroundActive &&
            controller.disableCalls == 1 &&
            assistant.modelStore.suspendCalls == 1,
      );
      expect(assistant.observerBloc.state.foregroundActive, isFalse);
      expect(assistant.observerBloc.state.activeGeneration, isNull);
      expect(cameraDeactivationStarted.isCompleted, isTrue);
      expect(controller.disableCalls, 1);
      expect(assistant.modelStore.suspendCalls, 1);

      await runtime.close();
    },
  );

  test(
    'deactivates the camera while slow speech cancellation settles',
    () async {
      final timers = _RuntimeTimerHarness();
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources(
        periodicTimerFactory: timers.create,
      );
      final speechCompletion = Completer<AppResult<void>>();
      final releaseSpeechStop = Completer<void>();
      assistant.speechSynthesizer.onSpeak = (_) => speechCompletion.future;
      assistant.speechSynthesizer.onStop = () async {
        await releaseSpeechStop.future;
        if (!speechCompletion.isCompleted) {
          speechCompletion.complete(const AppSuccess<void>(null));
        }
        return const AppSuccess<void>(null);
      };
      final generation = FakeGenerationHandle();
      assistant.commentGenerator.onGenerate = (_) async => AppSuccess(generation);
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
      );
      timers.current.fire();
      await _waitForCondition(
        () => assistant.observerBloc.state.activeGeneration == ObserverGenerationKind.automatic,
      );
      generation.succeed('A chair is visible.');
      await _waitForCondition(
        () => assistant.observerBloc.state.isSpeaking,
      );

      final deactivation = runtime.setAssistantDestinationActive(active: false);
      await _waitForCondition(
        () => assistant.speechSynthesizer.stopCalls == 1 && controller.disableCalls == 1,
      );

      expect(assistant.observerBloc.state.foregroundActive, isTrue);
      expect(controller.disableCalls, 1);

      releaseSpeechStop.complete();
      await deactivation;

      expect(assistant.observerBloc.state.foregroundActive, isFalse);
      expect(assistant.observerBloc.state.isSpeaking, isFalse);
      await runtime.close();
    },
  );

  test(
    'deactivates the camera while slow microphone cancellation settles',
    () async {
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources(
        handsFreeInitiallyEnabled: true,
      );
      final releaseMicrophoneStop = Completer<AppResult<void>>();
      assistant.speechRecognizer.onHandleStop = () => releaseMicrophoneStop.future;
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.voicePhase == VoiceAgentPhase.watching,
      );

      final deactivation = runtime.setAssistantDestinationActive(active: false);
      await _waitForCondition(
        () => assistant.speechRecognizer.activeHandleStopCalls == 1 && controller.disableCalls == 1,
      );

      expect(assistant.observerBloc.state.foregroundActive, isTrue);
      expect(controller.disableCalls, 1);

      releaseMicrophoneStop.complete(const AppSuccess<void>(null));
      await deactivation;

      expect(assistant.observerBloc.state.foregroundActive, isFalse);
      expect(assistant.observerBloc.state.voicePhase, VoiceAgentPhase.unavailable);
      await runtime.close();
    },
  );

  test(
    'settles camera work before suspending the assistant runtime',
    () async {
      final disableStarted = Completer<void>();
      final releaseDisable = Completer<void>();
      final controller = FakeCameraController(
        onDisable: () async {
          disableStarted.complete();
          await releaseDisable.future;
        },
      );
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await disableStarted.future;

      expect(assistant.modelStore.suspendCalls, 0);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );

      releaseDisable.complete();
      await _waitForCondition(
        () =>
            assistant.modelStore.suspendCalls == 1 &&
            assistant.observerBloc.state.modelStatus == ObserverModelStatus.suspended,
      );

      expect(assistant.modelStore.suspendCalls, 1);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.suspended,
      );

      await runtime.close();
    },
  );

  test(
    'rejects queued suspension after a rapid foreground return',
    () async {
      final disableStarted = Completer<void>();
      final releaseDisable = Completer<void>();
      final controller = FakeCameraController(
        onDisable: () async {
          disableStarted.complete();
          await releaseDisable.future;
        },
      );
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      await _waitForCondition(
        () => assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready,
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await disableStarted.future;
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      releaseDisable.complete();
      await _waitForCondition(
        () => assistant.observerBloc.state.foregroundActive && controller.enableCalls.length == 2,
      );

      expect(assistant.modelStore.suspendCalls, 0);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );

      await runtime.close();
    },
  );

  test(
    'closes the model-pack coordinator before consumers and model stores',
    () async {
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final piperStore = _PassivePiperModelStore();
      final modelPackController = ModelPackController(
        qwenStore: assistant.modelStore,
        visionVerifier: TestVisionModelVerifier(),
        piperStore: piperStore,
        asrStore: assistant.asrModelStore,
        receiptStore: const _EmptyModelPackReceiptStore(),
        capacityReader: () async => 2 * 1024 * 1024 * 1024,
        fingerprint: 'runtime-close-order-v1',
        qwenDownloadBytes: 1,
        piperDownloadBytes: 1,
        asrDownloadBytes: 1,
      );
      var coordinatorClosedBeforeDependents = false;
      final coordinatorClosed = Completer<void>();
      final modelPackSubscription = modelPackController.states.listen(
        (_) {},
        onDone: () {
          coordinatorClosedBeforeDependents =
              !assistant.observerBloc.isClosed &&
              assistant.modelStore.closeCalls == 0 &&
              assistant.asrModelStore.closeCalls == 0 &&
              piperStore.closeCalls == 0;
          coordinatorClosed.complete();
        },
      );
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
        modelPackController: modelPackController,
        standalonePiperModelStore: piperStore,
      );
      await runtime.start();

      await runtime.close();
      await coordinatorClosed.future;

      expect(coordinatorClosedBeforeDependents, isTrue);
      expect(piperStore.closeCalls, 1);
      await modelPackSubscription.cancel();
    },
  );

  test(
    'settles camera-side shutdown before closing assistant resources',
    () async {
      final cameraCloseStarted = Completer<void>();
      final releaseCameraClose = Completer<void>();
      final controller = FakeCameraController(
        onClose: () async {
          cameraCloseStarted.complete();
          await releaseCameraClose.future;
        },
      );
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();
      assistant.observerBloc.add(
        const ObserverHandsFreeEnabledChanged(enabled: true),
      );
      if (assistant.observerBloc.state.voicePhase != VoiceAgentPhase.watching) {
        await assistant.observerBloc.stream.firstWhere(
          (state) => state.voicePhase == VoiceAgentPhase.watching,
        );
      }

      final closeTask = runtime.close();
      await cameraCloseStarted.future;

      expect(assistant.speechRecognizer.activeHandleStopCalls, 1);
      expect(assistant.modelStore.closeCalls, 0);
      expect(assistant.asrModelStore.closeCalls, 0);
      expect(assistant.commentGenerator.closeCalls, 0);
      expect(assistant.speechRecognizer.closeCalls, 0);
      expect(assistant.speechSynthesizer.closeCalls, 0);

      releaseCameraClose.complete();
      await closeTask;

      expect(assistant.modelStore.closeCalls, 1);
      expect(assistant.asrModelStore.closeCalls, 1);
      expect(assistant.commentGenerator.closeCalls, 1);
      expect(assistant.speechRecognizer.closeCalls, 1);
      expect(assistant.speechSynthesizer.closeCalls, 1);
    },
  );

  test(
    'closes assistant resources after camera shutdown fails and preserves the error',
    () async {
      final cameraCloseStarted = Completer<void>();
      final releaseCameraClose = Completer<void>();
      final cameraCloseFailure = StateError('camera close failed');
      final controller = FakeCameraController(
        onClose: () async {
          cameraCloseStarted.complete();
          await releaseCameraClose.future;
          throw cameraCloseFailure;
        },
      );
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();

      final closeTask = runtime.close();
      await cameraCloseStarted.future;

      expect(assistant.modelStore.closeCalls, 0);
      expect(assistant.asrModelStore.closeCalls, 0);
      expect(assistant.commentGenerator.closeCalls, 0);
      expect(assistant.speechRecognizer.closeCalls, 0);
      expect(assistant.speechSynthesizer.closeCalls, 0);

      releaseCameraClose.complete();
      await expectLater(
        closeTask,
        throwsA(same(cameraCloseFailure)),
      );
      expect(assistant.modelStore.closeCalls, 1);
      expect(assistant.asrModelStore.closeCalls, 1);
      expect(assistant.commentGenerator.closeCalls, 1);
      expect(assistant.speechRecognizer.closeCalls, 1);
      expect(assistant.speechSynthesizer.closeCalls, 1);
    },
  );

  test('retries retained assistant ownership after terminal close fails', () async {
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    final closeFailure = Exception('native destroy failed');
    assistant.commentGenerator.closeFailures.add(closeFailure);
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    await runtime.start();

    await expectLater(runtime.close(), throwsA(same(closeFailure)));
    expect(assistant.commentGenerator.closeCalls, 1);

    await runtime.close();
    await runtime.close();

    expect(assistant.commentGenerator.closeCalls, 2);
    expect(assistant.speechSynthesizer.closeCalls, 1);
  });

  test('retries a retained system speech owner after close fails', () async {
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    const closeFailure = DeviceUnavailableFailure(
      code: 'test_speech_close_failed',
    );
    assistant.speechSynthesizer.closeFailures.add(closeFailure);
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    await runtime.start();

    await expectLater(
      runtime.close(),
      throwsA(
        isA<AppRuntimeCloseException>().having(
          (error) => error.failure,
          'failure',
          same(closeFailure),
        ),
      ),
    );
    expect(assistant.speechSynthesizer.closeCalls, 1);

    await runtime.close();
    await runtime.close();

    expect(assistant.speechSynthesizer.closeCalls, 2);
  });

  test('retries a retained speech recognizer after close fails', () async {
    final controller = FakeCameraController();
    final sceneSession = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final assistant = TestAssistantResources();
    const closeFailure = DeviceUnavailableFailure(
      code: 'test_asr_close_failed',
    );
    assistant.speechRecognizer.closeFailures.add(closeFailure);
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      sceneSession: sceneSession,
      observerBloc: assistant.observerBloc,
      modelStore: assistant.modelStore,
      asrModelStore: assistant.asrModelStore,
      commentGenerator: assistant.commentGenerator,
      speechRecognizer: assistant.speechRecognizer,
      speechSynthesizer: assistant.speechSynthesizer,
    );
    await runtime.start();

    await expectLater(
      runtime.close(),
      throwsA(
        isA<AppRuntimeCloseException>().having(
          (error) => error.failure,
          'failure',
          same(closeFailure),
        ),
      ),
    );
    expect(assistant.speechRecognizer.closeCalls, 1);

    await runtime.close();
    await runtime.close();

    expect(assistant.speechRecognizer.closeCalls, 2);
  });

  test(
    'closes the recognizer when ASR-store close fails and retries the store',
    () async {
      final controller = FakeCameraController();
      final sceneSession = ObservationSceneSession(
        controller: controller,
        stabilizer: SceneStabilizer(),
      );
      final assistant = TestAssistantResources();
      final closeFailure = Exception('ASR store close failed');
      assistant.asrModelStore.closeFailures.add(closeFailure);
      final runtime = AppRuntime(
        cameraBloc: CameraBloc(controller),
        sceneSession: sceneSession,
        observerBloc: assistant.observerBloc,
        modelStore: assistant.modelStore,
        asrModelStore: assistant.asrModelStore,
        commentGenerator: assistant.commentGenerator,
        speechRecognizer: assistant.speechRecognizer,
        speechSynthesizer: assistant.speechSynthesizer,
      );
      await runtime.start();

      await expectLater(runtime.close(), throwsA(same(closeFailure)));
      expect(assistant.asrModelStore.closeCalls, 1);
      expect(assistant.speechRecognizer.closeCalls, 1);

      await runtime.close();
      await runtime.close();

      expect(assistant.asrModelStore.closeCalls, 2);
      expect(assistant.speechRecognizer.closeCalls, 1);
    },
  );
}

Future<void> _waitForCondition(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected asynchronous runtime state to settle.');
}

final class _RuntimeTimerHarness {
  final List<_RuntimePeriodicTimer> created = [];

  _RuntimePeriodicTimer get current => created.last;

  Timer create(Duration duration, void Function() onTick) {
    final timer = _RuntimePeriodicTimer(onTick);
    created.add(timer);
    return timer;
  }
}

final class _RuntimePeriodicTimer implements Timer {
  _RuntimePeriodicTimer(this._onTick);

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

final class _PassivePiperModelStore implements CacheVerifyingModelStore<VerifiedPiperModelBundle> {
  final StreamController<ModelStoreState<VerifiedPiperModelBundle>> _states = StreamController.broadcast(sync: true);

  @override
  ModelStoreState<VerifiedPiperModelBundle> current = const ModelStoreState.idle();

  int closeCalls = 0;

  @override
  Stream<ModelStoreState<VerifiedPiperModelBundle>> get states => _states.stream;

  @override
  Future<AppResult<VerifiedPiperModelBundle>> prepare() async {
    return const AppError<VerifiedPiperModelBundle>(
      DeviceUnavailableFailure(code: 'test_piper_not_prepared'),
    );
  }

  @override
  Future<AppResult<bool>> verifyCache() async {
    return const AppSuccess(false);
  }

  @override
  Future<void> suspend() async {
    current = const ModelStoreState.suspended();
    if (!_states.isClosed) _states.add(current);
  }

  @override
  Future<void> close() async {
    if (_states.isClosed) return;
    closeCalls += 1;
    await _states.close();
  }
}

final class _EmptyModelPackReceiptStore implements ModelPackReceiptStore {
  const _EmptyModelPackReceiptStore();

  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String fingerprint) async {}
}
