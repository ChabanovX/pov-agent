import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';

import '../../support/fake_camera_controller.dart';
import '../../support/test_app_dependencies.dart';

void main() {
  testWidgets('keeps runtime cold until the mandatory model pack completes', (
    tester,
  ) async {
    final dependencies = await createTestAppRuntime(FakeCameraController());
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
        () => dependencies.modelPackController.current.phase == ModelPackPhase.ready,
      );

      expect(find.text('Set up your on-device AI'), findsOneWidget);
      expect(find.byType(CupertinoTabBar), findsNothing);
      expect(dependencies.runtime.observerBloc.state.started, isFalse);
      expect(dependencies.cameraController.initCalls, 0);

      await tester.tap(find.text('Download models'));
      await _pumpUntil(
        tester,
        () => dependencies.runtime.observerBloc.state.started,
      );

      final tabBar = tester.widget<CupertinoTabBar>(
        find.byType(CupertinoTabBar),
      );
      expect(tabBar.items.map((item) => item.label), ['Assistant', 'Settings']);
      expect(find.text('Set up your on-device AI'), findsNothing);
      expect(find.byKey(assistantPromptFieldKey), findsOneWidget);
      expect(find.byKey(testObservationSurfaceKey), findsNothing);
      expect(dependencies.cameraController.initCalls, 1);
      expect(dependencies.cameraController.enableCalls, isEmpty);
    } finally {
      await _disposeDependencies(tester, dependencies);
    }
  });

  testWidgets('quiesces Assistant resources only while Settings is selected', (
    tester,
  ) async {
    final dependencies = await createTestAppRuntime(
      FakeCameraController(),
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

      await tester.tap(find.text('Continue'));
      await _pumpUntil(
        tester,
        () => dependencies.cameraController.enableCalls.length == 1,
      );
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);

      await tester.tap(_tabLabel('Settings'));
      await _pumpUntil(
        tester,
        () => !dependencies.runtime.observerBloc.state.foregroundActive,
      );

      expect(find.byKey(const ValueKey('settings-scroll-view')), findsOneWidget);
      expect(find.byKey(testObservationSurfaceKey), findsNothing);
      expect(dependencies.cameraController.disableCalls, 1);
      expect(dependencies.assistant.modelStore.prepareCalls, 2);

      await tester.tap(_tabLabel('Assistant'));
      await _pumpUntil(
        tester,
        () =>
            dependencies.runtime.observerBloc.state.foregroundActive &&
            dependencies.cameraController.enableCalls.length == 2,
      );

      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
      expect(dependencies.assistant.modelStore.prepareCalls, 2);
      expect(
        tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
        0,
      );
    } finally {
      await _disposeDependencies(tester, dependencies);
    }
  });
}

Finder _tabLabel(String label) {
  return find.descendant(
    of: find.byType(CupertinoTabBar),
    matching: find.text(label),
  );
}

Future<void> _disposeDependencies(
  WidgetTester tester,
  TestAppRuntime dependencies,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final closeTask = disposeTestAppRuntime(dependencies);
  var settled = false;
  Object? failure;
  StackTrace? failureStackTrace;
  unawaited(
    closeTask.then<void>(
      (_) => settled = true,
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
        settled = true;
      },
    ),
  );
  await _pumpUntil(tester, () => settled);
  if (failure case final error?) {
    Error.throwWithStackTrace(error, failureStackTrace!);
  }
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
  throw TestFailure('Expected router operation to settle.');
}
