import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pov_agent/features/assistant/data/datasources/permission_handler_microphone_permission_gateway.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  test('accepts granted microphone permission', () async {
    final gateway = PermissionHandlerMicrophonePermissionGateway(
      requestPermission: () async => PermissionStatus.granted,
    );

    expect(await gateway.request(), isA<AppSuccess<void>>());
  });

  for (final entry in <PermissionStatus, String>{
    PermissionStatus.denied: 'microphone_permission_denied',
    PermissionStatus.restricted: 'microphone_permission_restricted',
    PermissionStatus.permanentlyDenied: 'microphone_permission_permanently_denied',
  }.entries) {
    test('normalizes ${entry.key.name} microphone permission', () async {
      final gateway = PermissionHandlerMicrophonePermissionGateway(
        requestPermission: () async => entry.key,
      );

      expect(await gateway.request(), _failureWithCode(entry.value));
    });
  }

  test('normalizes plugin exceptions without swallowing Errors', () async {
    final exceptionGateway = PermissionHandlerMicrophonePermissionGateway(
      requestPermission: () => Future.error(Exception('channel unavailable')),
    );
    final programmerError = StateError('programmer failure');
    final errorGateway = PermissionHandlerMicrophonePermissionGateway(
      requestPermission: () => Future.error(programmerError),
    );

    expect(
      await exceptionGateway.request(),
      _failureWithCode('microphone_permission_request_failed'),
    );
    await expectLater(errorGateway.request(), throwsA(same(programmerError)));
  });
}

Matcher _failureWithCode(String code) {
  return isA<AppError<void>>().having(
    (result) => result.failure,
    'failure',
    isA<AppFailure>().having((failure) => failure.code, 'code', code),
  );
}
