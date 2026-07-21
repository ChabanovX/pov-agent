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
import 'package:pov_agent/shared/domain/app_result.dart';

import '../../support/fake_assistant_runtime.dart';
import '../../support/fake_camera_controller.dart';
import '../../support/test_assistant_resources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owns camera and scene startup and shutdown exactly once', (
    tester,
  ) async {
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
      commentGenerator: assistant.commentGenerator,
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

    await tester.runAsync(runtime.close);
    await tester.runAsync(runtime.close);
    await sceneChangesComplete;

    expect(controller.closeCalls, 1);
    expect(assistant.modelStore.closeCalls, 1);
    expect(assistant.commentGenerator.closeCalls, 1);
  });

  testWidgets('close before start prevents later resource acquisition', (
    tester,
  ) async {
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
      commentGenerator: assistant.commentGenerator,
    );
    final sceneChangesComplete = expectLater(
      sceneSession.changes,
      emitsDone,
    );

    await tester.runAsync(runtime.close);
    await sceneChangesComplete;

    final rejectedStart = runtime.start();
    expect(identical(rejectedStart, runtime.start()), isTrue);
    await expectLater(rejectedStart, throwsStateError);
    expect(controller.initCalls, 0);
    expect(controller.closeCalls, 1);
  });

  testWidgets('close wins an immediate overlap with startup', (
    tester,
  ) async {
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
      commentGenerator: assistant.commentGenerator,
    );
    final sceneChangesComplete = expectLater(
      sceneSession.changes,
      emitsDone,
    );

    await tester.runAsync(() async {
      final startTask = runtime.start();
      final closeTask = runtime.close();
      expect(identical(closeTask, runtime.close()), isTrue);
      await Future.wait([startTask, closeTask]);
    });
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
      commentGenerator: assistant.commentGenerator,
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

  testWidgets(
    'suspends and reloads the eager observer session',
    (tester) async {
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
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(assistant.modelStore.suspendCalls, 1);
      expect(controller.disableCalls, 1);

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(assistant.modelStore.prepareCalls, 3);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );
      expect(controller.enableCalls, hasLength(3));

      await tester.runAsync(runtime.close);
    },
  );

  testWidgets(
    'quiesces generation before deactivating the camera',
    (tester) async {
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
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();
      await tester.pumpAndSettle();
      assistant.observerBloc.add(
        const ObserverPromptSubmitted('Describe the scene'),
      );
      await tester.pumpAndSettle();
      expect(
        assistant.observerBloc.state.activeGeneration,
        ObserverGenerationKind.manual,
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();

      expect(handle.cancelCalls, 1);
      expect(controller.disableCalls, 0);
      await tester.runAsync(() async {
        releaseCancellation.complete();
        await handle.cancel();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(assistant.observerBloc.state.foregroundActive, isFalse);
      expect(assistant.observerBloc.state.activeGeneration, isNull);
      expect(cameraDeactivationStarted.isCompleted, isTrue);
      expect(controller.disableCalls, 1);
      expect(assistant.modelStore.suspendCalls, 1);

      await tester.runAsync(runtime.close);
    },
  );

  testWidgets(
    'settles camera work before suspending the assistant runtime',
    (tester) async {
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
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();
      assistant.observerBloc.add(const ObserverStarted());
      await tester.pumpAndSettle();

      runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      await disableStarted.future;

      expect(assistant.modelStore.suspendCalls, 0);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );

      releaseDisable.complete();
      await tester.pumpAndSettle();

      expect(assistant.modelStore.suspendCalls, 1);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.suspended,
      );

      await tester.runAsync(runtime.close);
    },
  );

  testWidgets(
    'rejects queued suspension after a rapid foreground return',
    (tester) async {
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
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();
      assistant.observerBloc.add(const ObserverStarted());
      await tester.pumpAndSettle();

      runtime.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      await disableStarted.future;
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      releaseDisable.complete();
      await tester.pumpAndSettle();

      expect(assistant.modelStore.suspendCalls, 0);
      expect(
        assistant.observerBloc.state.modelStatus,
        ObserverModelStatus.ready,
      );

      await tester.runAsync(runtime.close);
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
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();

      final closeTask = runtime.close();
      await cameraCloseStarted.future;

      expect(assistant.modelStore.closeCalls, 0);
      expect(assistant.commentGenerator.closeCalls, 0);

      releaseCameraClose.complete();
      await closeTask;

      expect(assistant.modelStore.closeCalls, 1);
      expect(assistant.commentGenerator.closeCalls, 1);
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
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();

      final closeTask = runtime.close();
      await cameraCloseStarted.future;

      expect(assistant.modelStore.closeCalls, 0);
      expect(assistant.commentGenerator.closeCalls, 0);

      releaseCameraClose.complete();
      await expectLater(
        closeTask,
        throwsA(same(cameraCloseFailure)),
      );
      expect(assistant.modelStore.closeCalls, 1);
      expect(assistant.commentGenerator.closeCalls, 1);
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
      commentGenerator: assistant.commentGenerator,
    );
    await runtime.start();

    await expectLater(runtime.close(), throwsA(same(closeFailure)));
    expect(assistant.commentGenerator.closeCalls, 1);

    await runtime.close();
    await runtime.close();

    expect(assistant.commentGenerator.closeCalls, 2);
  });
}
