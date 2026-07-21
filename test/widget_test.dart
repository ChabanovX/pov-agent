import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';

import 'support/fake_camera_controller.dart';
import 'support/test_app_dependencies.dart';

void main() {
  testWidgets('keeps camera observation active behind the Assistant tab', (
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

      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(tester.widget<Title>(find.byType(Title)).title, 'POV Agent');
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
      expect(find.byKey(assistantPromptFieldKey), findsNothing);
      expect(controller.enableCalls, hasLength(1));
      expect(
        tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
        0,
      );

      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();

      expect(find.byKey(testObservationSurfaceKey), findsNothing);
      expect(find.byKey(assistantPromptFieldKey), findsOneWidget);
      expect(controller.disableCalls, 0);
      expect(
        tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
        1,
      );

      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
      expect(controller.enableCalls, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await _pumpUntil(tester, () => controller.disableCalls == 1);
      expect(controller.disableCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await _pumpUntil(tester, () => controller.enableCalls.length == 2);
      expect(controller.enableCalls, hasLength(2));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => disposeTestAppRuntime(runtime));
    }
  });

  testWidgets('keeps a manual camera disable across tab switches', (
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

      await tester.tap(find.bySemanticsLabel('Disable camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(find.text('Camera is off.'), findsOneWidget);
      expect(controller.enableCalls, hasLength(1));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => disposeTestAppRuntime(runtime));
    }
  });

  testWidgets('router recreation reuses the app-owned camera session', (
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(controller.closeCalls, 0);

      await tester.pumpWidget(
        const PovAgentApp(
          observationSurfaceBuilder: buildTestObservationSurface,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
      expect(controller.initCalls, 1);
      expect(controller.closeCalls, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => disposeTestAppRuntime(runtime));
    }
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (predicate()) return;
  }
  throw TestFailure('Expected lifecycle operation to settle.');
}
