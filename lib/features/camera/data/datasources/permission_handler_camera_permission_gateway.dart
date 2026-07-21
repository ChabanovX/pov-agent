import 'package:permission_handler/permission_handler.dart';
import 'package:pov_agent/features/camera/application/ports/camera_permission_gateway.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Testable boundary around the plugin's camera permission request.
typedef RequestCameraPermission = Future<PermissionStatus> Function();

/// Opens the platform application-settings surface.
typedef OpenCameraApplicationSettings = Future<bool> Function();

/// A camera permission gateway backed by `permission_handler`.
final class PermissionHandlerCameraPermissionGateway implements CameraPermissionGateway {
  /// Creates the production gateway.
  PermissionHandlerCameraPermissionGateway({
    RequestCameraPermission? requestPermission,
    OpenCameraApplicationSettings? openApplicationSettings,
  }) : _requestPermission = requestPermission ?? (() => Permission.camera.request()),
       _openApplicationSettings = openApplicationSettings ?? openAppSettings;

  final RequestCameraPermission _requestPermission;
  final OpenCameraApplicationSettings _openApplicationSettings;

  @override
  Future<AppResult<void>> request() async {
    try {
      final status = await _requestPermission();
      if (status.isGranted) return const AppSuccess<void>(null);
      return AppError<void>(
        PermissionDeniedFailure(
          code: status.isPermanentlyDenied
              ? 'camera_permission_permanently_denied'
              : status.isRestricted
              ? 'camera_permission_restricted'
              : 'camera_permission_denied',
        ),
      );
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(
        UnexpectedFailure(
          code: 'camera_permission_request_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> openApplicationSettings() async {
    try {
      if (await _openApplicationSettings()) {
        return const AppSuccess<void>(null);
      }
      return const AppError<void>(
        DeviceUnavailableFailure(code: 'camera_settings_unavailable'),
      );
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(
        UnexpectedFailure(
          code: 'camera_permission_settings_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
