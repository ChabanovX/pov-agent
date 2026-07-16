import 'package:some_camera_with_llm/features/camera/application/models/observation_event.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// Controls one live YOLO observation session without exposing plugin types.
abstract interface class ObservationController {
  Stream<ObservationEvent> get events;

  Future<AppResult<CameraCapabilities>> init();

  Future<AppResult<void>> enable(CameraLens lens);

  Future<AppResult<void>> disable();

  Future<AppResult<void>> retryModel();

  Future<void> close();
}
