import 'package:get_it/get_it.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/app/widgets/native_camera_preview.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/flutter_camera_driver.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/camera_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/repositories/camera_controller_impl.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_cubit.dart';

final GetIt appDependencies = GetIt.instance;

AppRuntime configureDependencies() {
  final driver = FlutterCameraDriver();
  final controller = CameraControllerImpl(
    driver,
    const CameraFailureMapper(),
  );
  final runtime = AppRuntime(
    cameraCubit: CameraCubit(controller),
    cameraPreview: NativeCameraPreview(driver: driver),
  );

  appDependencies.registerSingleton<AppRuntime>(runtime);
  return runtime;
}
