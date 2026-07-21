import 'package:pov_agent/shared/domain/app_result.dart';

/// A boundary for foreground microphone permission requests.
abstract interface class MicrophonePermissionGateway {
  /// Requests microphone access and returns any denial as an [AppError].
  Future<AppResult<void>> request();

  /// Opens this application's platform settings for permission recovery.
  Future<AppResult<void>> openApplicationSettings();
}
