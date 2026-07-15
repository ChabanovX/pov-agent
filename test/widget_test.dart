import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/app/app.dart';

import 'support/fake_camera_controller.dart';

void main() {
  testWidgets('suspends the camera while the Assistant tab is visible', (
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

    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byKey(testCameraPreviewKey), findsOneWidget);
    expect(find.text('Assistant placeholder'), findsNothing);
    expect(controller.enableCalls, hasLength(1));
    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      0,
    );

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();

    expect(find.byKey(testCameraPreviewKey), findsNothing);
    expect(find.text('Assistant placeholder'), findsOneWidget);
    expect(controller.disableCalls, 1);
    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      1,
    );

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(find.byKey(testCameraPreviewKey), findsOneWidget);
    expect(controller.enableCalls, hasLength(2));

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pumpAndSettle();
    expect(controller.disableCalls, 2);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(controller.enableCalls, hasLength(3));
  });

  testWidgets('keeps a manual camera disable across tab switches', (
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

    await tester.tap(find.bySemanticsLabel('Disable camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(find.text('Camera is off.'), findsOneWidget);
    expect(controller.enableCalls, hasLength(1));
  });
}
