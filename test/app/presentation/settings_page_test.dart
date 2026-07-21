import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/app/presentation/pages/settings_page.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/domain/entities/observer_interval.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';

import '../../support/fake_camera_controller.dart';
import '../../support/test_assistant_resources.dart';

void main() {
  testWidgets('edits session-only audio, hands-free, and interval settings', (
    tester,
  ) async {
    final fixture = await _SettingsFixture.create();
    try {
      await tester.pumpWidget(fixture.buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Observation'), findsOneWidget);
      expect(find.text('Audio and voice'), findsOneWidget);
      expect(find.text('Models'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(fixture.assistant.observerBloc.state.handsFreeEnabled, isFalse);
      expect(fixture.assistant.microphonePermissionGateway.requestCalls, 0);

      await tester.tap(find.byType(CupertinoSwitch).first);
      await _pumpUntil(
        tester,
        () => fixture.assistant.observerBloc.state.speechMuted,
      );

      await tester.tap(find.byType(CupertinoSwitch).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Enable hands-free listening'), findsOneWidget);
      expect(fixture.assistant.microphonePermissionGateway.requestCalls, 0);

      await tester.tap(find.text('Enable microphone'));
      await _pumpUntil(
        tester,
        () => fixture.assistant.observerBloc.state.handsFreeEnabled,
      );
      expect(fixture.assistant.microphonePermissionGateway.requestCalls, 1);

      await tester.tap(find.text('Comment interval'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 sec'));
      await _pumpUntil(
        tester,
        () => fixture.assistant.observerBloc.state.interval == ObserverInterval.thirtySeconds,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(fixture.close());
    }
  });

  testWidgets('renders the iOS inset-grouped Settings composition', (
    tester,
  ) async {
    final fixture = await _SettingsFixture.create();
    try {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      await tester.pumpWidget(fixture.buildApp());
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(SettingsPage),
        matchesGoldenFile('goldens/settings_page.png'),
      );
    } finally {
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(fixture.close());
    }
  });
}

final class _SettingsFixture {
  _SettingsFixture._({
    required this.cameraBloc,
    required this.assistant,
  });

  final CameraBloc cameraBloc;
  final TestAssistantResources assistant;

  static Future<_SettingsFixture> create() async {
    final cameraBloc = CameraBloc(
      FakeCameraController(),
      initiallyRequestedEnabled: false,
    );
    final assistant = TestAssistantResources();
    assistant.observerBloc.add(const ObserverStarted());
    await assistant.observerBloc.stream.firstWhere(
      (state) => state.modelStatus == ObserverModelStatus.ready,
    );
    return _SettingsFixture._(
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
          child: SettingsPage(modelPackState: _verifiedModelPackState()),
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

ModelPackState _verifiedModelPackState() {
  return ModelPackState(
    phase: ModelPackPhase.complete,
    availableStorageBytes: ModelPackState.requiredStorageBytes,
    items: const [
      ModelPackItemState(
        kind: ModelPackItemKind.assistant,
        technicalName: 'Qwen3-0.6B',
        downloadBytes: 1,
        phase: ModelPackItemPhase.verified,
      ),
      ModelPackItemState(
        kind: ModelPackItemKind.vision,
        technicalName: 'YOLO26n',
        downloadBytes: 0,
        phase: ModelPackItemPhase.verified,
      ),
      ModelPackItemState(
        kind: ModelPackItemKind.voice,
        technicalName: 'Piper',
        downloadBytes: 1,
        phase: ModelPackItemPhase.verified,
      ),
      ModelPackItemState(
        kind: ModelPackItemKind.listening,
        technicalName: 'ASR',
        downloadBytes: 1,
        phase: ModelPackItemPhase.verified,
      ),
    ],
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
  throw TestFailure('Expected asynchronous UI state to settle.');
}
