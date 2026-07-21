import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';

import 'support/fake_camera_controller.dart';
import 'support/test_app_dependencies.dart';

void main() {
  testWidgets('renders the verified two-destination application shell', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);
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

      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(tester.widget<Title>(find.byType(Title)).title, 'POV Agent');
      expect(
        tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).items.map((item) => item.label),
        ['Assistant', 'Settings'],
      );
      expect(find.byKey(assistantPromptFieldKey), findsOneWidget);
      expect(find.text('Let Assistant see the scene'), findsOneWidget);
      expect(find.byKey(testObservationSurfaceKey), findsNothing);
      expect(dependencies.cameraController.enableCalls, isEmpty);

      await tester.tap(find.text('Continue'));
      await _pumpUntil(
        tester,
        () => dependencies.cameraController.enableCalls.length == 1,
      );

      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
      expect(dependencies.cameraController.initCalls, 1);
    } finally {
      await _disposeDependencies(tester, dependencies);
    }
  });

  testWidgets('keeps an explicit camera pause across destination switches', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);
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

      await tester.tap(find.bySemanticsLabel('Disable camera'));
      await _pumpUntil(
        tester,
        () => !dependencies.runtime.cameraBloc.state.requestedEnabled,
      );
      await tester.tap(_tabLabel('Settings'));
      await _pumpUntil(
        tester,
        () => !dependencies.runtime.observerBloc.state.foregroundActive,
      );
      await tester.tap(_tabLabel('Assistant'));
      await _pumpUntil(
        tester,
        () => dependencies.runtime.observerBloc.state.foregroundActive,
      );

      expect(find.byKey(testObservationSurfaceKey), findsNothing);
      expect(find.text('Paused'), findsWidgets);
      expect(dependencies.cameraController.enableCalls, hasLength(1));
    } finally {
      await _disposeDependencies(tester, dependencies);
    }
  });

  testWidgets('covers scene content and releases resources in background', (
    tester,
  ) async {
    _useIPhone15Viewport(tester);
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _pumpUntil(
        tester,
        () => dependencies.cameraController.disableCalls == 1,
      );

      expect(
        find.byKey(const ValueKey('app-privacy-cover')),
        findsOneWidget,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpUntil(
        tester,
        () => dependencies.cameraController.enableCalls.length == 2,
      );

      expect(find.byKey(const ValueKey('app-privacy-cover')), findsNothing);
      expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
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

void _useIPhone15Viewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  throw TestFailure('Expected application operation to settle.');
}
