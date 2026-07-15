import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:some_camera_with_llm/app/app.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';

import '../test/support/fake_camera_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('camera controls and tab lifecycle work end to end', (
    tester,
  ) async {
    final controller = FakeCameraController();
    await tester.pumpWidget(
      SomeCameraWithLlmApp(
        cameraController: controller,
        cameraPreviewBuilder: buildTestCameraPreview,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(testCameraPreviewKey), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Switch camera'));
    await tester.pumpAndSettle();
    expect(controller.enableCalls.last, CameraLens.front);

    await tester.tap(find.bySemanticsLabel('Disable camera'));
    await tester.pumpAndSettle();
    expect(find.text('Camera is off.'), findsOneWidget);

    await tester.tap(find.text('Enable camera'));
    await tester.pumpAndSettle();
    expect(find.byKey(testCameraPreviewKey), findsOneWidget);

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    expect(find.text('Assistant placeholder'), findsOneWidget);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.byKey(testCameraPreviewKey), findsOneWidget);
  });
}
