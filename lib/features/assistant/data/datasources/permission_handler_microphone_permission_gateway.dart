import 'package:permission_handler/permission_handler.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Testable boundary around the plugin's microphone permission request.
typedef RequestMicrophonePermission = Future<PermissionStatus> Function();

/// Opens the platform application-settings surface.
typedef OpenMicrophoneApplicationSettings = Future<bool> Function();

/// A microphone permission gateway backed by `permission_handler`.
final class PermissionHandlerMicrophonePermissionGateway implements MicrophonePermissionGateway {
  /// Creates the production gateway.
  PermissionHandlerMicrophonePermissionGateway({
    RequestMicrophonePermission? requestPermission,
    OpenMicrophoneApplicationSettings? openApplicationSettings,
  }) : _requestPermission = requestPermission ?? (() => Permission.microphone.request()),
       _openApplicationSettings = openApplicationSettings ?? openAppSettings;

  final RequestMicrophonePermission _requestPermission;
  final OpenMicrophoneApplicationSettings _openApplicationSettings;

  @override
  Future<AppResult<void>> request() async {
    try {
      final status = await _requestPermission();
      if (status.isGranted) return const AppSuccess<void>(null);
      return AppError<void>(
        PermissionDeniedFailure(
          code: status.isPermanentlyDenied
              ? 'microphone_permission_permanently_denied'
              : status.isRestricted
              ? 'microphone_permission_restricted'
              : 'microphone_permission_denied',
        ),
      );
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(
        UnexpectedFailure(
          code: 'microphone_permission_request_failed',
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
        DeviceUnavailableFailure(
          code: 'microphone_permission_settings_unavailable',
        ),
      );
    } on Object catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError<void>(
        UnexpectedFailure(
          code: 'microphone_permission_settings_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
