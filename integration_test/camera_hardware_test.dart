import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';

const _runHardwareCameraTest = bool.fromEnvironment(
  'RUN_HARDWARE_CAMERA_TEST',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real live YOLO surface survives controls and visibility changes',
    (tester) async {
      final runtime = configureDependencies();
      await runtime.start();
      try {
        await tester.pumpWidget(const PovAgentApp());
        await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));

        await tester.tap(find.bySemanticsLabel('Switch camera'));
        await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();
        expect(find.text('Assistant placeholder'), findsOneWidget);

        await tester.tap(find.text('Camera'));
        await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));

        await tester.tap(find.bySemanticsLabel('Disable camera'));
        await tester.pumpAndSettle();
        expect(find.text('Camera is off.'), findsOneWidget);

        await tester.tap(find.text('Enable camera'));
        await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));
      } finally {
        await runtime.close();
        await appDependencies.reset(dispose: false);
      }
    },
    skip: !_runHardwareCameraTest,
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt += 1) {
    await tester.pump(AppAnimations.regular.slow);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the live YOLO controls.');
}
