import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/presentation/pages/assistant_camera_page.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import '../../support/fake_camera_controller.dart';
import '../../support/test_assistant_resources.dart';

void main() {
  testWidgets(
    'keeps native camera unmounted until contextual Continue is tapped',
    (tester) async {
      final fixture = await _AssistantPageFixture.create();
      try {
        await tester.pumpWidget(fixture.buildApp());
        await tester.pumpAndSettle();

        expect(find.text('Let Assistant see the scene'), findsOneWidget);
        expect(find.byKey(testObservationSurfaceKey), findsNothing);
        expect(fixture.controller.enableCalls, isEmpty);
        expect(find.text('Ask about the detected scene...'), findsOneWidget);

        await tester.tap(find.text('Continue'));
        await _pumpUntil(
          tester,
          () => fixture.cameraBloc.state.status == CameraStatus.enabled,
        );

        expect(find.byKey(testObservationSurfaceKey), findsOneWidget);
        expect(fixture.controller.enableCalls, hasLength(1));
        expect(find.text('Watching'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(fixture.close());
      }
    },
  );

  testWidgets('camera denial preserves typed questions and opens Settings', (
    tester,
  ) async {
    final fixture = await _AssistantPageFixture.create(
      cameraController: FakeCameraController(
        enableFailure: const PermissionDeniedFailure(
          code: 'camera_permission_denied',
        ),
      ),
    );
    try {
      String? generatedPrompt;
      fixture.assistant.commentGenerator.onGenerate = (request) async {
        generatedPrompt = request.prompt;
        return const AppError(
          UnexpectedFailure(code: 'test_manual_generation_failure'),
        );
      };
      await tester.pumpWidget(fixture.buildApp());
      await tester.enterText(
        find.byKey(assistantPromptFieldKey),
        'What can you see without the camera?',
      );
      await tester.tap(find.text('Continue'));
      await _pumpUntil(
        tester,
        () => fixture.cameraBloc.state.status == CameraStatus.failure,
      );

      expect(find.text('No camera context'), findsWidgets);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(
        find.text('What can you see without the camera?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Open Settings'));
      await _pumpUntil(
        tester,
        () => fixture.controller.openPermissionSettingsCalls == 1,
      );
      expect(fixture.controller.openPermissionSettingsCalls, 1);

      await tester.tap(find.byKey(const ValueKey('assistant-send-button')));
      await _pumpUntil(tester, () => generatedPrompt != null);
      expect(
        generatedPrompt,
        contains('What can you see without the camera?'),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(fixture.close());
    }
  });

  testWidgets('renders the camera-first iOS composition at phone size', (
    tester,
  ) async {
    final fixture = await _AssistantPageFixture.create();
    try {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      await tester.pumpWidget(fixture.buildApp());
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AssistantCameraPage),
        matchesGoldenFile('goldens/assistant_camera_permission.png'),
      );
    } finally {
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(fixture.close());
    }
  });
}

final class _AssistantPageFixture {
  _AssistantPageFixture._({
    required this.controller,
    required this.cameraBloc,
    required this.assistant,
  });

  final FakeCameraController controller;
  final CameraBloc cameraBloc;
  final TestAssistantResources assistant;

  static Future<_AssistantPageFixture> create({
    FakeCameraController? cameraController,
  }) async {
    final controller = cameraController ?? FakeCameraController();
    final cameraBloc = CameraBloc(
      controller,
      initiallyRequestedEnabled: false,
    )..add(const CameraStarted());
    final assistant = TestAssistantResources();
    assistant.observerBloc.add(const ObserverStarted());
    await Future.wait<void>([
      cameraBloc.stream
          .firstWhere(
            (state) => state.status == CameraStatus.disabled && state.availableLenses.isNotEmpty,
          )
          .then<void>((_) {}),
      assistant.observerBloc.stream
          .firstWhere(
            (state) => state.modelStatus == ObserverModelStatus.ready,
          )
          .then<void>((_) {}),
    ]);
    return _AssistantPageFixture._(
      controller: controller,
      cameraBloc: cameraBloc,
      assistant: assistant,
    );
  }

  Widget buildApp() {
    return CupertinoApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(393, 852),
          padding: AppSpacing.regular.referencePhoneSafeArea,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cameraBloc),
            BlocProvider.value(value: assistant.observerBloc),
          ],
          child: const AssistantCameraPage(
            surfaceBuilder: buildTestObservationSurface,
          ),
        ),
      ),
    );
  }

  Future<void> close() async {
    final observerClose = assistant.observerBloc.close();
    final cameraClose = cameraBloc.close();
    await Future.wait<void>([observerClose, cameraClose]);
    await assistant.speechRecognizer.close();
    await assistant.speechSynthesizer.close();
    await assistant.commentGenerator.close();
    await assistant.asrModelStore.close();
    await assistant.modelStore.close();
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
  throw TestFailure('Expected asynchronous UI state to settle.');
}
