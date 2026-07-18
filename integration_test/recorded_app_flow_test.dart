import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:some_camera_with_llm/app/app.dart';
import 'package:some_camera_with_llm/app/di/app_di.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/features/camera/presentation/widgets/recorded_observation_surface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'normal app renders recorded YOLO without camera hardware',
    (tester) async {
      final runtime = configureDependencies();
      final semantics = tester.ensureSemantics();
      await runtime.start();
      try {
        await tester.pumpWidget(const SomeCameraWithLlmApp());
        await _pumpUntilFound(tester, find.byType(RecordedObservationSurface));
        await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));
        final personDetection = find.semantics.byLabel(
          RegExp(r'^person \d+%$'),
        );
        final diagnostics = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.startsWith('FPS ') ?? false) &&
              (widget.data?.contains('Inference ') ?? false),
        );
        await _pumpUntilFound(tester, personDetection);
        await _pumpUntilFound(tester, diagnostics);

        expect(find.byType(Image), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(RecordedObservationSurface),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        expect(personDetection, findsAtLeast(1));
        expect(find.bySemanticsLabel('Switch camera'), findsNothing);
        expect(diagnostics, findsOneWidget);

        final firstFrameBytes = Uint8List.fromList(
          _displayedFrameBytes(tester),
        );
        await _pumpUntilCondition(
          tester,
          () => !listEquals(firstFrameBytes, _displayedFrameBytes(tester)),
        );

        await tester.tap(find.bySemanticsLabel('Disable camera'));
        await _pumpUntilFound(tester, find.text('Enable camera'));
        expect(personDetection, findsNothing);

        await tester.tap(find.text('Enable camera'));
        await _pumpUntilFound(tester, personDetection);

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();
        expect(find.text('Assistant placeholder'), findsOneWidget);

        await tester.tap(find.text('Camera'));
        await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));
      } finally {
        semantics.dispose();
        await runtime.close();
        await appDependencies.reset(dispose: false);
      }
    },
    timeout: Timeout(AppAnimations.regular.slow * 1000),
  );
}

Uint8List _displayedFrameBytes(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  final provider = image.image;
  if (provider is MemoryImage) return provider.bytes;
  fail('Recorded observation did not render a MemoryImage frame.');
}

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    await tester.pump(AppAnimations.regular.normal);
    if (condition()) return;
  }
  fail('Timed out waiting for the recorded video frame to change.');
}

Future<void> _pumpUntilFound<CandidateType>(
  WidgetTester tester,
  FinderBase<CandidateType> finder,
) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    await tester.pump(AppAnimations.regular.normal);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for recorded observation UI.');
}
