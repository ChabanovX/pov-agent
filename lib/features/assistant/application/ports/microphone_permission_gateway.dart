import 'package:pov_agent/shared/domain/app_result.dart';

/// A boundary for foreground microphone permission requests.
// ignore: one_member_abstracts
abstract interface class MicrophonePermissionGateway {
  /// Requests microphone access and returns any denial as an [AppError].
  Future<AppResult<void>> request();
}
