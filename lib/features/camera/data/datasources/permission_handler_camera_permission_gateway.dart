import 'package:permission_handler/permission_handler.dart';
import 'package:some_camera_with_llm/core/errors/failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/camera_permission_gateway.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

final class PermissionHandlerCameraPermissionGateway implements CameraPermissionGateway {
  const PermissionHandlerCameraPermissionGateway(this._failureMapper);

  final FailureMapper _failureMapper;

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
      return AppError<void>(_failureMapper.map(error, stackTrace));
    }
  }
}
