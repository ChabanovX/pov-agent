import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// Requests the foreground camera permission before a native view is mounted.
///
/// This one-method port keeps the platform permission plugin replaceable in
/// deterministic tests.
// ignore: one_member_abstracts
abstract interface class CameraPermissionGateway {
  Future<AppResult<void>> request();
}
