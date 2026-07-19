import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/app.dart';

import '../../support/fake_camera_controller.dart';
import '../../support/test_app_dependencies.dart';
import '../../support/test_assistant_resources.dart';

void main() {
  testWidgets('starts the app-owned assistant only on its first tab visit', (
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

      expect(modelStore.prepareCalls, 0);
      expect(runtime.assistantBloc.state.started, isFalse);

      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      expect(modelStore.prepareCalls, 1);
      expect(runtime.assistantBloc.state.started, isTrue);

      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();
      expect(modelStore.prepareCalls, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => disposeTestAppRuntime(runtime));
    }
  });
}
