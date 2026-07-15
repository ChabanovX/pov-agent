import 'package:camera/camera.dart' as plugin;
import 'package:some_camera_with_llm/core/errors/failure_mapper.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

final class CameraFailureMapper implements FailureMapper {
  const CameraFailureMapper();

  @override
  AppFailure map(Object error, StackTrace stackTrace) {
    if (error is plugin.CameraException) {
      return switch (error.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' => PermissionDeniedFailure(
          message: error.description,
          cause: error,
          stackTrace: stackTrace,
        ),
        'cameraNotFound' || 'CameraNotFound' => DeviceUnavailableFailure(
          message: error.description,
          cause: error,
          stackTrace: stackTrace,
        ),
        _ => UnexpectedFailure(
          code: 'camera_${error.code}',
          message: error.description,
          cause: error,
          stackTrace: stackTrace,
        ),
      };
    }

    return UnexpectedFailure(cause: error, stackTrace: stackTrace);
  }
}
