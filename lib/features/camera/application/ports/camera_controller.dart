import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_frame.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// Controls one camera session without exposing platform plugin types.
abstract interface class CameraController {
  Stream<AppResult<CameraFrame>> get frames;

  Future<AppResult<CameraCapabilities>> init();

  Future<AppResult<void>> enable(CameraLens lens);

  Future<AppResult<void>> disable();

  Future<void> close();
}
