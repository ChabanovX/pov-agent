import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/app/widgets/observation_surface.dart';
import 'package:some_camera_with_llm/core/constants/compilation_constants.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/observation_controller.dart';
import 'package:some_camera_with_llm/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/method_channel_recorded_video_frame_source.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/permission_handler_camera_permission_gateway.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/repositories/recorded_frame_detector_impl.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:some_camera_with_llm/features/camera/presentation/widgets/recorded_observation_surface.dart';

/// The application composition container.
final GetIt appDependencies = GetIt.instance;

const _recordedVideoAssetPath = 'assets/video/pedestrians.mp4';

/// Composes and registers the runtime selected by [CompilationConstants].
AppRuntime configureDependencies() {
  final (
    ObservationController controller,
    Widget surface,
  ) = CompilationConstants.usesRecordedVideo
      ? _recordedObservationComposition()
      : _cameraObservationComposition();
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(controller),
    observationSurface: surface,
  );

  appDependencies.registerSingleton<AppRuntime>(runtime);
  return runtime;
}

(ObservationController, Widget) _cameraObservationComposition() {
  final observationAdapter = YoloObservationAdapter(
    cameraPermissionGateway: const PermissionHandlerCameraPermissionGateway(
      YoloFailureMapper(),
    ),
    resultMapper: const YoloResultMapper(),
    failureMapper: const YoloFailureMapper(),
  );
  return (observationAdapter, ObservationSurface(adapter: observationAdapter));
}

(ObservationController, Widget) _recordedObservationComposition() {
  final detector = RecordedFrameDetectorImpl(
    UltralyticsRecordedFrameInference(),
    const YoloResultMapper(),
    const YoloFailureMapper(),
  );
  final observationAdapter = RecordedObservationAdapter(
    detector: detector,
    frameSource: MethodChannelRecordedVideoFrameSource(
      assetPath: _recordedVideoAssetPath,
    ),
  );
  return (
    observationAdapter,
    RecordedObservationSurface(frameSource: observationAdapter),
  );
}
