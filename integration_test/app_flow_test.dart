import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';

import '../test/support/fake_camera_controller.dart';
import '../test/support/test_app_dependencies.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Assistant and Settings lifecycle works end to end', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final dependencies = await createTestAppRuntime(
      controller,
      modelPackComplete: true,
    );
    try {
      await tester.pumpWidget(
        PovAgentApp(
          runtime: dependencies.runtime,
          modelPackController: dependencies.modelPackController,
          observationSurfaceBuilder: buildTestObservationSurface,
        ),
      );
      await _pumpUntil(
        tester,
        () => dependencies.runtime.observerBloc.state.started,
      );

      expect(find.text('Let Assistant see the scene'), findsOneWidget);
      expect(find.byKey(testObservationSurfaceKey), findsNothing);

      await tester.tap(find.text('Continue'));
      await _pumpUntil(tester, () => controller.enableCalls.length == 1);
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Switch camera'));
      await _pumpUntil(tester, () => controller.enableCalls.length == 2);
      expect(controller.enableCalls.last, CameraLens.front);

      await tester.tap(find.bySemanticsLabel('Disable camera'));
      await _pumpUntil(
        tester,
        () => !dependencies.runtime.cameraBloc.state.requestedEnabled,
      );
      expect(find.text('Paused'), findsWidgets);
      expect(find.byKey(testObservationSurfaceKey), findsNothing);

      await tester.tap(find.bySemanticsLabel('Enable camera'));
      await _pumpUntil(tester, () => controller.enableCalls.length == 3);
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);

      await tester.tap(_tabLabel('Settings'));
      await _pumpUntil(
        tester,
        () => !dependencies.runtime.observerBloc.state.foregroundActive,
      );
      expect(find.byKey(const ValueKey('settings-scroll-view')), findsOneWidget);
      expect(find.byKey(testObservationSurfaceKey), findsNothing);

      await tester.tap(_tabLabel('Assistant'));
      await _pumpUntil(
        tester,
        () => dependencies.runtime.observerBloc.state.foregroundActive && controller.enableCalls.length == 4,
      );
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      final closeTask = disposeTestAppRuntime(dependencies);
      var closed = false;
      Object? failure;
      StackTrace? failureStackTrace;
      unawaited(
        closeTask.then<void>(
          (_) => closed = true,
          onError: (Object error, StackTrace stackTrace) {
            failure = error;
            failureStackTrace = stackTrace;
            closed = true;
          },
        ),
      );
      await _pumpUntil(tester, () => closed);
      if (failure case final error?) {
        Error.throwWithStackTrace(error, failureStackTrace!);
      }
    }
  });
}

Finder _tabLabel(String label) {
  return find.descendant(
    of: find.byType(CupertinoTabBar),
    matching: find.text(label),
  );
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
  throw TestFailure('Expected application operation to settle.');
}
