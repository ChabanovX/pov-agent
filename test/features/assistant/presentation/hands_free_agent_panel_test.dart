import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/widgets/hands_free_agent_panel.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

void main() {
  testWidgets('projects ASR preparation, download, and verification', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.loading,
        voicePhase: VoiceAgentPhase.preparing,
      ),
    );
    expect(find.text('Preparing on-device speech recognition…'), findsOneWidget);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.downloading,
        asrModelDownloadProgress: 0.42,
        voicePhase: VoiceAgentPhase.preparing,
      ),
    );
    expect(find.text('Downloading speech recognition: 42%'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.value == '42%',
      ),
      findsOneWidget,
    );

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.verifying,
        voicePhase: VoiceAgentPhase.preparing,
      ),
    );
    expect(find.text('Verifying on-device speech recognition…'), findsOneWidget);
  });

  testWidgets('projects the complete active hands-free turn', (tester) async {
    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'hey camera',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.watching,
      ),
    );
    expect(find.text('Say “Hey camera” to ask about the current scene.'), findsOneWidget);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.wakeDetected,
        voiceQuestionDraft: 'what is',
      ),
    );
    expect(find.text('Wake phrase detected. Ask your question.'), findsOneWidget);
    expect(find.text('Heard: what is'), findsOneWidget);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.listening,
        voiceQuestionDraft: 'what is in front of me',
      ),
    );
    expect(find.text('Listening for your question…'), findsOneWidget);
    expect(find.text('Heard: what is in front of me'), findsOneWidget);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.thinking,
        voiceQuestionDraft: 'what is in front of me',
        voiceAnswerDraft: 'A person is standing',
      ),
    );
    expect(find.text('Thinking about your question…'), findsOneWidget);
    expect(find.text('Question: what is in front of me'), findsOneWidget);
    expect(find.text('Answering: A person is standing'), findsOneWidget);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.speaking,
        voiceQuestionDraft: 'what is in front of me',
      ),
    );
    expect(find.text('Speaking the answer…'), findsOneWidget);
    expect(find.text('Question: what is in front of me'), findsOneWidget);
  });

  testWidgets('maps permission, recognition, and model failures to retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    void retry() => retries += 1;

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.failure,
        voiceFailure: const PermissionDeniedFailure(
          code: 'microphone_permission_denied',
        ),
      ),
      onRetry: retry,
    );
    expect(
      find.text('Microphone access is off. Allow it in Settings, then retry.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(handsFreeAgentRetryButtonKey));
    expect(retries, 1);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'hey camera',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.failure,
        voiceFailure: const UnexpectedFailure(
          code: 'voice_question_empty',
        ),
      ),
      onRetry: retry,
    );
    expect(
      find.text('No question was heard. Say “Hey camera” and try again.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(handsFreeAgentRetryButtonKey));
    expect(retries, 2);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.ready,
        voicePhase: VoiceAgentPhase.failure,
        voiceFailure: const DeviceUnavailableFailure(
          code: 'asr_stream_failed',
        ),
      ),
      onRetry: retry,
    );
    expect(
      find.text('Speech recognition stopped. Retry hands-free listening.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(handsFreeAgentRetryButtonKey));
    expect(retries, 3);

    await _pumpPanel(
      tester,
      ObserverState(
        wakePhrase: 'assistant',
        started: true,
        asrModelStatus: ObserverModelStatus.failure,
        voicePhase: VoiceAgentPhase.failure,
        asrModelFailure: const NetworkFailure(code: 'model_download'),
      ),
      onRetry: retry,
    );
    expect(
      find.text(
        'The speech model could not be downloaded. Check your connection and retry.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(handsFreeAgentRetryButtonKey));
    expect(retries, 4);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ObserverState state, {
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: CupertinoPageScaffold(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HandsFreeAgentPanel(
              state: state,
              onRetry: onRetry ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
