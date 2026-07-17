import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:some_camera_with_llm/app/app.dart';
import 'package:some_camera_with_llm/app/di/app_di.dart';
import 'package:some_camera_with_llm/app/di/observation_source.dart';
import 'package:some_camera_with_llm/core/design_system/tokens/tokens.dart';
import 'package:some_camera_with_llm/features/camera/presentation/widgets/recorded_observation_surface.dart';

const _runRecordedAppTest = bool.fromEnvironment(
  'RUN_RECORDED_APP_TEST',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'normal app renders recorded YOLO without camera hardware',
    (tester) async {
      final runtime = configureDependencies(
        observationSource: ObservationSource.recorded,
      );
      final semantics = tester.ensureSemantics();
      await runtime.start();
      try {
        await tester.pumpWidget(const SomeCameraWithLlmApp());
        await _pumpUntilFound(
          tester,
          find.byType(RecordedObservationSurface),
        );
        await _pumpUntilFound(
          tester,
          find.bySemanticsLabel('Disable camera'),
        );
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

        await tester.tap(find.bySemanticsLabel('Disable camera'));
        await _pumpUntilFound(tester, find.text('Enable camera'));
        expect(personDetection, findsNothing);

        await tester.tap(find.text('Enable camera'));
        await _pumpUntilFound(tester, personDetection);

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();
        expect(find.text('Assistant placeholder'), findsOneWidget);

        await tester.tap(find.text('Camera'));
        await _pumpUntilFound(
          tester,
          find.bySemanticsLabel('Disable camera'),
        );
      } finally {
        semantics.dispose();
        await runtime.close();
        await appDependencies.reset(dispose: false);
      }
    },
    skip: !_runRecordedAppTest,
    timeout: Timeout(AppAnimations.regular.slow * 1000),
  );
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
