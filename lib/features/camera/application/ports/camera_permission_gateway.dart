import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// A boundary for foreground camera permission requests.
///
/// This one-method port keeps the platform permission plugin replaceable in
/// deterministic tests.
// ignore: one_member_abstracts
abstract interface class CameraPermissionGateway {
  /// Requests camera access and returns any denial as an [AppError].
  Future<AppResult<void>> request();
}
