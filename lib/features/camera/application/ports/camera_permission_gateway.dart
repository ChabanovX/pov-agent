import 'package:pov_agent/shared/domain/app_result.dart';

/// A boundary for foreground camera permission and recovery actions.
abstract interface class CameraPermissionGateway {
  /// Requests camera access and returns any denial as an [AppError].
  Future<AppResult<void>> request();

  /// Opens the platform application settings after permission is denied.
  Future<AppResult<void>> openApplicationSettings();
}
