import 'package:get_it/get_it.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/datasources/method_channel_recorded_video_frame_source.dart';
import 'package:pov_agent/features/camera/data/datasources/permission_handler_camera_permission_gateway.dart';
import 'package:pov_agent/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:pov_agent/features/camera/data/repositories/recorded_frame_detector_impl.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';

/// The application composition container.
final GetIt appDependencies = GetIt.instance;

const _recordedVideoAssetPath = 'assets/video/pedestrians.mp4';

/// Composes and registers the runtime selected by [CompilationConstants].
AppRuntime configureDependencies() {
  final controller = CompilationConstants.usesRecordedVideo
      ? _registerRecordedObservation()
      : _registerCameraObservation();
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(controller),
  );

  appDependencies
    ..registerSingleton<ObservationController>(controller)
    ..registerSingleton<AppRuntime>(runtime);
  return runtime;
}

YoloObservationAdapter _registerCameraObservation() {
  final observationAdapter = YoloObservationAdapter(
    cameraPermissionGateway: const PermissionHandlerCameraPermissionGateway(),
  );
  appDependencies.registerSingleton<YoloObservationAdapter>(
    observationAdapter,
  );
  return observationAdapter;
}

RecordedObservationAdapter _registerRecordedObservation() {
  final detector = RecordedFrameDetectorImpl(
    UltralyticsRecordedFrameInference(),
  );
  final observationAdapter = RecordedObservationAdapter(
    detector: detector,
    frameSource: MethodChannelRecordedVideoFrameSource(
      assetPath: _recordedVideoAssetPath,
    ),
  );
  appDependencies
    ..registerSingleton<RecordedObservationAdapter>(observationAdapter)
    ..registerSingleton<RecordedObservationFrameSource>(observationAdapter);
  return observationAdapter;
}
