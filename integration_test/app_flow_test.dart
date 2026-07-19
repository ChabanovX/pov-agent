import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/features/assistant/presentation/pages/assistant_page.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';

import '../test/support/fake_camera_controller.dart';
import '../test/support/test_app_dependencies.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('camera controls and tab lifecycle work end to end', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final runtime = await startTestAppRuntime(controller);
    try {
      await tester.pumpWidget(
        const PovAgentApp(
          observationSurfaceBuilder: buildTestObservationSurface,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Switch camera'));
      await tester.pumpAndSettle();
      expect(controller.enableCalls.last, CameraLens.front);

      await tester.tap(find.bySemanticsLabel('Disable camera'));
      await tester.pumpAndSettle();
      expect(find.text('Camera is off.'), findsOneWidget);

      await tester.tap(find.text('Enable camera'));
      await tester.pumpAndSettle();
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);

      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantPage), findsOneWidget);

      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => disposeTestAppRuntime(runtime));
    }
  });
}
