import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';

import 'fake_camera_controller.dart';

Future<AppRuntime> startTestAppRuntime(
  FakeCameraController controller,
) async {
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(controller),
  );
  appDependencies.registerSingleton<AppRuntime>(runtime);
  await runtime.start();
  return runtime;
}

Future<void> disposeTestAppRuntime(AppRuntime runtime) async {
  await runtime.close();
  await appDependencies.reset(dispose: false);
}
