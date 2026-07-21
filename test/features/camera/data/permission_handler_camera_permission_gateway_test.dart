import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pov_agent/features/camera/data/datasources/permission_handler_camera_permission_gateway.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  test('accepts granted camera permission', () async {
    final gateway = PermissionHandlerCameraPermissionGateway(
      requestPermission: () async => PermissionStatus.granted,
    );

    expect(await gateway.request(), isA<AppSuccess<void>>());
  });

  for (final entry in <PermissionStatus, String>{
    PermissionStatus.denied: 'camera_permission_denied',
    PermissionStatus.restricted: 'camera_permission_restricted',
    PermissionStatus.permanentlyDenied: 'camera_permission_permanently_denied',
  }.entries) {
    test('normalizes ${entry.key.name} camera permission', () async {
      final gateway = PermissionHandlerCameraPermissionGateway(
        requestPermission: () async => entry.key,
      );

      expect(await gateway.request(), _failureWithCode(entry.value));
    });
  }

  test('normalizes plugin exceptions without swallowing Errors', () async {
    final exceptionGateway = PermissionHandlerCameraPermissionGateway(
      requestPermission: () => Future.error(Exception('channel unavailable')),
    );
    final programmerError = StateError('programmer failure');
    final errorGateway = PermissionHandlerCameraPermissionGateway(
      requestPermission: () => Future.error(programmerError),
    );

    expect(
      await exceptionGateway.request(),
      _failureWithCode('camera_permission_request_failed'),
    );
    await expectLater(errorGateway.request(), throwsA(same(programmerError)));
  });

  test('opens application settings for denied-permission recovery', () async {
    var openCalls = 0;
    final gateway = PermissionHandlerCameraPermissionGateway(
      openApplicationSettings: () async {
        openCalls += 1;
        return true;
      },
    );

    expect(
      await gateway.openApplicationSettings(),
      isA<AppSuccess<void>>(),
    );
    expect(openCalls, 1);
  });

  test('normalizes unavailable application settings and plugin exceptions', () async {
    final unavailable = PermissionHandlerCameraPermissionGateway(
      openApplicationSettings: () async => false,
    );
    final exceptional = PermissionHandlerCameraPermissionGateway(
      openApplicationSettings: () => Future.error(Exception('unavailable')),
    );

    expect(
      await unavailable.openApplicationSettings(),
      _failureWithCode('camera_settings_unavailable'),
    );
    expect(
      await exceptional.openApplicationSettings(),
      _failureWithCode('camera_permission_settings_failed'),
    );
  });
}

Matcher _failureWithCode(String code) {
  return isA<AppError<void>>().having(
    (result) => result.failure,
    'failure',
    isA<AppFailure>().having((failure) => failure.code, 'code', code),
  );
}
