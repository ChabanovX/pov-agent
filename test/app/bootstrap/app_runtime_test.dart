import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_state.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';

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
      assistantBloc: assistant.assistantBloc,
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
      assistantBloc: assistant.assistantBloc,
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
      assistantBloc: assistant.assistantBloc,
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
      assistantBloc: assistant.assistantBloc,
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
    'suspends and reloads only a lazily started assistant session',
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
        assistantBloc: assistant.assistantBloc,
        modelStore: assistant.modelStore,
        commentGenerator: assistant.commentGenerator,
      );
      await runtime.start();

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(assistant.modelStore.suspendCalls, 0);

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      assistant.assistantBloc.add(const AssistantStarted());
      await tester.pumpAndSettle();
      expect(assistant.modelStore.prepareCalls, 1);
      expect(
        assistant.assistantBloc.state.modelStatus,
        AssistantModelStatus.ready,
      );

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(assistant.modelStore.suspendCalls, 1);
      expect(
        assistant.assistantBloc.state.modelStatus,
        AssistantModelStatus.suspended,
      );

      runtime
        ..didChangeAppLifecycleState(AppLifecycleState.hidden)
        ..didChangeAppLifecycleState(AppLifecycleState.inactive)
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(assistant.modelStore.prepareCalls, 2);
      expect(
        assistant.assistantBloc.state.modelStatus,
        AssistantModelStatus.ready,
      );

      await tester.runAsync(runtime.close);
    },
  );
}
