import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('platform channel reports model-cache volume capacity', (
    tester,
  ) async {
    await tester.runAsync<void>(() async {
      final directory = await const ApplicationSupportModelDirectoryProvider().resolve();
      await directory.create(recursive: true);

      final availableBytes = await MethodChannelModelDiskCapacityGateway().availableBytes(directory.path);

      expect(availableBytes, greaterThan(0));
    });
  });
}
