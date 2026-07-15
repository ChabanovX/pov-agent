import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:some_camera_with_llm/app/app.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';

const _runHardwareCameraTest = bool.fromEnvironment(
  'RUN_HARDWARE_CAMERA_TEST',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real camera preview survives controls and visibility changes',
    (tester) async {
      await tester.pumpWidget(const SomeCameraWithLlmApp());
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
    },
    skip: !_runHardwareCameraTest,
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump(AppAnimations.regular.slow);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the real camera controls.');
}
