import 'package:permission_handler/permission_handler.dart';
import 'package:pov_agent/features/camera/application/ports/camera_permission_gateway.dart';
import 'package:pov_agent/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A camera permission gateway backed by `permission_handler`.
final class PermissionHandlerCameraPermissionGateway implements CameraPermissionGateway {
  /// Creates a camera permission gateway.
  const PermissionHandlerCameraPermissionGateway();

  @override
  Future<AppResult<void>> request() async {
    try {
      final status = await Permission.camera.request();
      if (status.isGranted) return const AppSuccess<void>(null);
      return AppError<void>(
        PermissionDeniedFailure(
          code: status.isPermanentlyDenied ? 'camera_permission_permanently_denied' : 'camera_permission_denied',
        ),
      );
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(YoloFailureMapper.map(error, stackTrace));
    }
  }
}
