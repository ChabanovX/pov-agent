import 'package:flutter/widgets.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/app/di/app_di.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_cubit.dart';

import 'fake_camera_controller.dart';

Future<AppRuntime> startTestAppRuntime(
  FakeCameraController controller,
) async {
  final runtime = AppRuntime(
    cameraCubit: CameraCubit(controller),
    cameraPreview: const Builder(builder: buildTestCameraPreview),
  );
  appDependencies.registerSingleton<AppRuntime>(runtime);
  await runtime.start();
  return runtime;
}

Future<void> disposeTestAppRuntime(AppRuntime runtime) async {
  await runtime.close();
  await appDependencies.reset(dispose: false);
}
