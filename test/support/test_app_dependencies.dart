import 'package:flutter/widgets.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/app/di/app_di.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';

import 'fake_camera_controller.dart';

Future<AppRuntime> startTestAppRuntime(
  FakeCameraController controller,
) async {
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(controller),
    observationSurface: const Builder(
      builder: buildTestObservationSurface,
    ),
  );
  appDependencies.registerSingleton<AppRuntime>(runtime);
  await runtime.start();
  return runtime;
}

Future<void> disposeTestAppRuntime(AppRuntime runtime) async {
  await runtime.close();
  await appDependencies.reset(dispose: false);
}
