import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pov_agent/model_storage');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('resolves the platform-owned no-backup model directory', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return '/platform/no-backup/models';
    });
    const provider = PlatformModelDirectoryProvider.withChannel(channel);

    final directory = await provider.resolve();

    expect(capturedCall?.method, 'resolveDirectory');
    expect(directory.path, '/platform/no-backup/models');
  });

  test('rejects an empty native model directory response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => '  ',
    );
    const provider = PlatformModelDirectoryProvider.withChannel(channel);

    await expectLater(provider.resolve(), throwsFormatException);
  });
}
