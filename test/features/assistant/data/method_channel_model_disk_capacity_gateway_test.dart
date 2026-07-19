import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/model_storage');
  const gateway = MethodChannelModelDiskCapacityGateway.withChannel(channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('passes the cache directory and returns native free bytes', () async {
    MethodCall? observedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        observedCall = call;
        return 987654321;
      },
    );

    expect(await gateway.availableBytes('/app/support/models'), 987654321);
    expect(observedCall?.method, 'availableBytes');
    expect(
      observedCall?.arguments,
      {'directoryPath': '/app/support/models'},
    );
  });

  test('rejects malformed native capacity payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => -1,
    );

    expect(
      gateway.availableBytes('/app/support/models'),
      throwsA(isA<FormatException>()),
    );
  });
}
