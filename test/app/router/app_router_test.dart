import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/app.dart';

import '../../support/fake_camera_controller.dart';
import '../../support/test_app_dependencies.dart';
import '../../support/test_assistant_resources.dart';

void main() {
  testWidgets('keeps the eager observer and camera active across tabs', (
    tester,
  ) async {
    final runtime = await startTestAppRuntime(FakeCameraController());
    final modelStore = runtime.modelStore as TestModelStore;
    try {
      await tester.pumpWidget(
        const PovAgentApp(
          observationSurfaceBuilder: buildTestObservationSurface,
        ),
      );
      await tester.pumpAndSettle();

      expect(modelStore.prepareCalls, 1);
      expect(runtime.observerBloc.state.started, isTrue);
      expect(runtime.cameraBloc.state.surfaceActive, isTrue);

      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      expect(modelStore.prepareCalls, 1);
      expect(runtime.observerBloc.state.started, isTrue);
      expect(runtime.cameraBloc.state.surfaceActive, isTrue);

      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      expect(modelStore.prepareCalls, 1);
      expect(runtime.cameraBloc.state.surfaceActive, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => disposeTestAppRuntime(runtime));
    }
  });
}
