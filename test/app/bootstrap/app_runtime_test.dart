import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
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
        () =>
            assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready &&
            assistant.observerBloc.state.voicePhase == VoiceAgentPhase.watching,
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
            assistant.observerBloc.state.voicePhase == VoiceAgentPhase.watching,
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
            assistant.observerBloc.state.voicePhase == VoiceAgentPhase.watching,
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
    'quiesces generation before deactivating the camera',
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
        () =>
            assistant.observerBloc.state.modelStatus == ObserverModelStatus.ready &&
            assistant.observerBloc.state.voicePhase == VoiceAgentPhase.watching,
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
      await _waitForCondition(() => handle.cancelCalls == 1);

      expect(handle.cancelCalls, 1);
      expect(controller.disableCalls, 0);
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
