import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

import 'fake_camera_controller.dart';
import 'test_assistant_resources.dart';

Future<AppRuntime> startTestAppRuntime(
  FakeCameraController controller,
) async {
  final sceneSession = ObservationSceneSession(
    controller: controller,
    stabilizer: SceneStabilizer(),
  );
  final assistant = TestAssistantResources(sceneSource: sceneSession);
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(controller),
    sceneSession: sceneSession,
    observerBloc: assistant.observerBloc,
    modelStore: assistant.modelStore,
    commentGenerator: assistant.commentGenerator,
    speechSynthesizer: assistant.speechSynthesizer,
  );
  appDependencies
    ..registerSingleton<SceneSource>(sceneSession)
    ..registerSingleton<AppRuntime>(runtime);
  await runtime.start();
  return runtime;
}

Future<void> disposeTestAppRuntime(AppRuntime runtime) async {
  await runtime.close();
  await appDependencies.reset(dispose: false);
}
