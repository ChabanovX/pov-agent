import 'package:get_it/get_it.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/app/widgets/observation_surface.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/permission_handler_camera_permission_gateway.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';

final GetIt appDependencies = GetIt.instance;

AppRuntime configureDependencies() {
  final observationAdapter = YoloObservationAdapter(
    cameraPermissionGateway: const PermissionHandlerCameraPermissionGateway(
      YoloFailureMapper(),
    ),
    resultMapper: const YoloResultMapper(),
    failureMapper: const YoloFailureMapper(),
  );
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(observationAdapter),
    cameraPreview: ObservationSurface(adapter: observationAdapter),
  );

  appDependencies.registerSingleton<AppRuntime>(runtime);
  return runtime;
}
