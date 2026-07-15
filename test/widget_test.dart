import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/app/app.dart';

import 'support/fake_camera_controller.dart';
import 'support/test_app_dependencies.dart';

void main() {
  testWidgets('suspends the camera while the Assistant tab is visible', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final runtime = await startTestAppRuntime(controller);
    try {
      await tester.pumpWidget(const SomeCameraWithLlmApp());
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
    } finally {
      await disposeTestAppRuntime(runtime);
    }
  });

  testWidgets('keeps a manual camera disable across tab switches', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final runtime = await startTestAppRuntime(controller);
    try {
      await tester.pumpWidget(const SomeCameraWithLlmApp());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Disable camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(find.text('Camera is off.'), findsOneWidget);
      expect(controller.enableCalls, hasLength(1));
    } finally {
      await disposeTestAppRuntime(runtime);
    }
  });

  testWidgets('router recreation reuses the app-owned camera session', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final runtime = await startTestAppRuntime(controller);
    try {
      await tester.pumpWidget(const SomeCameraWithLlmApp());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(controller.closeCalls, 0);

      await tester.pumpWidget(const SomeCameraWithLlmApp());
      await tester.pumpAndSettle();

      expect(find.byKey(testCameraPreviewKey), findsOneWidget);
      expect(controller.initCalls, 1);
      expect(controller.closeCalls, 0);
    } finally {
      await disposeTestAppRuntime(runtime);
    }
  });
}
