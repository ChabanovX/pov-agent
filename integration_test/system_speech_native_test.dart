import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/core/design_system/app_theme.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/core/l10n/app_localizations.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/data/adapters/flutter_tts_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/assistant/presentation/pages/assistant_page.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import '../test/support/fake_assistant_runtime.dart';

const _runSystemSpeechTest = bool.fromEnvironment(
  'RUN_SYSTEM_SPEECH_TEST',
);
final Duration _nativeEvidenceTimeout = AppAnimations.regular.slow * 42;
final Duration _operationTimeout = AppAnimations.regular.slow * 125;
final Duration _closeTimeout = AppAnimations.regular.slow * 42;
final Duration _lateCallbackDrain = AppAnimations.regular.slow * 6;
final Duration _pollInterval = AppAnimations.regular.fast;
final Timeout _integrationTestTimeout = Timeout(
  AppAnimations.regular.slow * 334,
);

const _naturalUtterance = 'The system voice is ready to describe the current scene.';
const _interruptibleUtterance =
    'This deliberately long system speech sample remains active while the '
    'acceptance test asks the native synthesizer to stop. It contains enough '
    'words to ensure that cancellation happens during playback instead of '
    'after an already completed utterance. The adapter must settle that stop '
    'before another replay reaches the native engine, otherwise a delayed '
    'cancellation callback could incorrectly terminate the newer speech.';
const _featureUtterance = 'A person is standing near the doorway while sunlight reaches the floor.';
const _mutedFeatureUtterance = 'A second completed comment remains silent while speech is muted.';
const _integrationOptions = GenerationOptions(
  maxTokens: 40,
  temperature: 0.7,
  topP: 0.8,
  topK: 20,
  minP: 0,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'system speech completes, stops, and replays without stale callbacks',
    (tester) async {
      if (!Platform.isIOS && !Platform.isAndroid) {
        fail(
          'System speech acceptance supports only iOS and Android, not '
          '${Platform.operatingSystem}.',
        );
      }

      final flutterTts = FlutterTts();
      final synthesizer = FlutterTtsSpeechSynthesizer(
        preferredLanguage: CompilationConstants.systemSpeechLanguage,
        flutterTts: flutterTts,
      );
      final progress = _NativeProgressProbe();
      flutterTts.setProgressHandler(progress.record);
      Object? primaryFailure;
      try {
        expect(CompilationConstants.systemSpeechLanguage, 'en-US');
        final naturalResult = await synthesizer.speak(_naturalUtterance).timeout(_operationTimeout);
        _expectSuccess(
          naturalResult,
          stage: 'natural_completion',
          synthesizer: synthesizer,
          progress: progress,
        );
        expect(progress.count, greaterThan(0));
        expect(progress.lastText, _naturalUtterance);
        expect(synthesizer.resolvedLanguage, startsWith('en-'));
        tester.printToConsole(
          'SYSTEM_SPEECH_ACCEPTANCE stage=natural_complete '
          'platform=${Platform.operatingSystem} '
          'locale=${synthesizer.resolvedLanguage} '
          'progress=${progress.count}',
        );

        final progressBeforeStop = progress.count;
        final interruptedSpeech = synthesizer.speak(
          _interruptibleUtterance,
        );
        await _waitForNativeEvidence(
          tester,
          progress: progress,
          minimumProgress: progressBeforeStop + 1,
          expectedText: _interruptibleUtterance,
          stage: 'stop_setup',
        );

        final stopResult = await synthesizer.stop().timeout(_operationTimeout);
        _expectSuccess(
          stopResult,
          stage: 'stop',
          synthesizer: synthesizer,
          progress: progress,
        );
        _expectSuccess(
          await interruptedSpeech.timeout(_operationTimeout),
          stage: 'interrupted_speech_settlement',
          synthesizer: synthesizer,
          progress: progress,
        );
        tester.printToConsole(
          'SYSTEM_SPEECH_ACCEPTANCE stage=stop_settled '
          'progress=${progress.count}',
        );

        final progressBeforeReplay = progress.count;
        final replay = synthesizer.speak(_naturalUtterance);
        await _waitForNativeEvidence(
          tester,
          progress: progress,
          minimumProgress: progressBeforeReplay + 1,
          expectedText: _naturalUtterance,
          stage: 'replay',
        );
        _expectSuccess(
          await replay.timeout(_operationTimeout),
          stage: 'replay_completion',
          synthesizer: synthesizer,
          progress: progress,
        );

        final progressAfterReplay = progress.count;
        await tester.pump(_lateCallbackDrain);
        expect(
          progress.count,
          progressAfterReplay,
          reason: 'No interrupted utterance may resume behind the replay.',
        );
        expect(progress.lastText, _naturalUtterance);
        _expectSuccess(
          await synthesizer.stop().timeout(_operationTimeout),
          stage: 'idle_stop_after_replay',
          synthesizer: synthesizer,
          progress: progress,
        );
        tester.printToConsole(
          'SYSTEM_SPEECH_ACCEPTANCE stage=complete '
          'progress=${progress.count} '
          'locale=${synthesizer.resolvedLanguage}',
        );
      } on Object catch (error) {
        primaryFailure = error;
        rethrow;
      } finally {
        final closeResult = await synthesizer.close().timeout(_closeTimeout);
        if (closeResult case AppError<void>(:final failure)) {
          final description = _failureDescription(failure);
          if (primaryFailure == null) {
            fail('System speech cleanup failed: $description.');
          }
          tester.printToConsole(
            'SYSTEM_SPEECH_ACCEPTANCE stage=cleanup_failure '
            'failure=$description',
          );
        }
      }
    },
    skip: !_runSystemSpeechTest,
    timeout: _integrationTestTimeout,
  );

  testWidgets(
    'observer UI drives native speech without queueing muted comments',
    (tester) async {
      if (!Platform.isIOS && !Platform.isAndroid) {
        fail(
          'System speech acceptance supports only iOS and Android, not '
          '${Platform.operatingSystem}.',
        );
      }

      final flutterTts = FlutterTts();
      final synthesizer = FlutterTtsSpeechSynthesizer(
        preferredLanguage: CompilationConstants.systemSpeechLanguage,
        flutterTts: flutterTts,
      );
      final progress = _NativeProgressProbe();
      flutterTts.setProgressHandler(progress.record);
      final store = FakeAssistantModelStore();
      final generator = FakeCommentGenerator();
      final scene = FakeSceneSource();
      final firstGeneration = FakeGenerationHandle();
      final mutedGeneration = FakeGenerationHandle();
      late void Function() fireTick;
      generator
        ..enqueueHandle(firstGeneration)
        ..enqueueHandle(mutedGeneration);
      final bloc = ObserverBloc(
        sceneSource: scene,
        modelStore: store,
        commentGenerator: generator,
        speechSynthesizer: synthesizer,
        requestBuilder: ObserverRequestBuilder(
          qwenPromptBuilder: QwenPromptBuilder(
            systemPrompt: 'Describe the stable scene briefly.',
            manualOptions: _integrationOptions,
            shortCommentOptions: _integrationOptions,
          ),
        ),
        periodicTimerFactory: (_, onTick) {
          fireTick = onTick;
          return _DormantTimer();
        },
      )..add(const ObserverStarted());

      Object? primaryFailure;
      try {
        await _pumpUntilState(
          tester,
          bloc,
          (state) => state.modelStatus == ObserverModelStatus.ready,
        );
        await tester.pumpWidget(
          CupertinoApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: BlocProvider.value(
              value: bloc,
              child: const AssistantPage(),
            ),
          ),
        );

        fireTick();
        await _pumpUntil(
          tester,
          () => generator.requests.length == 1,
          stage: 'first_generation_start',
        );
        await tester.runAsync(() async {
          firstGeneration.succeed(_featureUtterance);
          await Future<void>.delayed(Duration.zero);
        });
        await _waitForNativeEvidence(
          tester,
          progress: progress,
          minimumProgress: 1,
          expectedText: _featureUtterance,
          stage: 'automatic_comment',
        );
        await _pumpUntilState(
          tester,
          bloc,
          (state) => state.comments.length == 1 && state.isSpeaking,
        );

        fireTick();
        fireTick();
        await tester.pump(AppAnimations.regular.slow);
        expect(
          generator.requests,
          hasLength(1),
          reason: 'Timer ticks must be ignored while speech is active.',
        );

        final firstCommentControl = find.byKey(
          observerCommentSpeechButtonKey(0),
        );
        await _centerControl(tester, firstCommentControl);
        await tester.tap(firstCommentControl);
        await _pumpUntilState(tester, bloc, (state) => !state.isSpeaking);

        final replayProgress = progress.count + 1;
        await tester.tap(firstCommentControl);
        await _waitForNativeEvidence(
          tester,
          progress: progress,
          minimumProgress: replayProgress,
          expectedText: _featureUtterance,
          stage: 'comment_replay',
        );
        await _pumpUntilState(tester, bloc, (state) => state.isSpeaking);

        final muteControl = find.byKey(observerSpeechMuteButtonKey);
        await _centerControl(tester, muteControl);
        await tester.tap(muteControl);
        await _pumpUntilState(
          tester,
          bloc,
          (state) => state.speechMuted && !state.isSpeaking,
        );
        final progressAfterMute = progress.count;

        fireTick();
        await _pumpUntil(
          tester,
          () => generator.requests.length == 2,
          stage: 'muted_generation_start',
        );
        await tester.runAsync(() async {
          mutedGeneration.succeed(_mutedFeatureUtterance);
          await Future<void>.delayed(Duration.zero);
        });
        await _pumpUntilState(
          tester,
          bloc,
          (state) => state.comments.length == 2,
        );
        await tester.pump(AppAnimations.regular.slow * 3);
        expect(
          progress.count,
          progressAfterMute,
          reason: 'Muted comments must commit as text without native speech.',
        );

        bloc.add(const ObserverSpeechMutedChanged(muted: false));
        await _pumpUntilState(tester, bloc, (state) => !state.speechMuted);
        await tester.pump(AppAnimations.regular.slow * 3);
        expect(
          progress.count,
          progressAfterMute,
          reason: 'Unmuting must not backfill a skipped comment.',
        );

        final secondCommentControl = find.byKey(
          observerCommentSpeechButtonKey(1),
        );
        await _centerControl(tester, secondCommentControl);
        await tester.tap(secondCommentControl);
        await _waitForNativeEvidence(
          tester,
          progress: progress,
          minimumProgress: progressAfterMute + 1,
          expectedText: _mutedFeatureUtterance,
          stage: 'explicit_muted_comment_replay',
        );
        bloc.add(const ObserverForegroundDeactivated());
        await _pumpUntilState(
          tester,
          bloc,
          (state) => !state.foregroundActive && !state.isSpeaking,
        );
        final progressAfterLifecycleStop = progress.count;
        bloc.add(const ObserverResumed());
        await _pumpUntilState(
          tester,
          bloc,
          (state) => state.foregroundActive,
        );
        await tester.pump(AppAnimations.regular.slow * 3);
        expect(
          progress.count,
          progressAfterLifecycleStop,
          reason: 'Foreground resume must not replay interrupted speech.',
        );
        tester.printToConsole(
          'SYSTEM_SPEECH_FEATURE stage=complete '
          'platform=${Platform.operatingSystem} '
          'locale=${synthesizer.resolvedLanguage} '
          'comments=${bloc.state.comments.length} '
          'progress=${progress.count}',
        );
      } on Object catch (error) {
        primaryFailure = error;
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await bloc.close();
        await scene.close();
        await store.close();
        await generator.close();
        final closeResult = await synthesizer.close().timeout(_closeTimeout);
        if (closeResult case AppError<void>(:final failure)) {
          final description = _failureDescription(failure);
          if (primaryFailure == null) {
            fail('System speech feature cleanup failed: $description.');
          }
          tester.printToConsole(
            'SYSTEM_SPEECH_FEATURE stage=cleanup_failure '
            'failure=$description',
          );
        }
      }
    },
    skip: !_runSystemSpeechTest,
    timeout: _integrationTestTimeout,
  );
}

Future<void> _centerControl(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
  );
  await tester.pump();
}

Future<void> _pumpUntilState(
  WidgetTester tester,
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate,
) {
  return _pumpUntil(
    tester,
    () => predicate(bloc.state),
    stage: 'observer_state',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String stage,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < _nativeEvidenceTimeout) {
    await tester.pump(_pollInterval);
    if (predicate()) return;
  }
  fail('Timed out waiting for $stage.');
}

Future<void> _waitForNativeEvidence(
  WidgetTester tester, {
  required _NativeProgressProbe progress,
  required int minimumProgress,
  required String expectedText,
  required String stage,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < _nativeEvidenceTimeout) {
    if (progress.count >= minimumProgress && progress.lastText == expectedText) {
      return;
    }
    await tester.pump(_pollInterval);
  }
  fail(
    'Timed out waiting for native speech evidence during $stage: '
    'progress=${progress.count}/$minimumProgress; '
    'lastText=${progress.lastText ?? 'none'}.',
  );
}

void _expectSuccess(
  AppResult<void> result, {
  required String stage,
  required FlutterTtsSpeechSynthesizer synthesizer,
  required _NativeProgressProbe progress,
}) {
  if (result case AppError<void>(:final failure)) {
    fail(
      'System speech failed during $stage: ${_failureDescription(failure)}; '
      'progress=${progress.count}; '
      'lastText=${progress.lastText ?? 'none'}; '
      'locale=${synthesizer.resolvedLanguage ?? 'unresolved'}.',
    );
  }
}

final class _NativeProgressProbe {
  int count = 0;
  String? lastText;

  void record(String text, int start, int end, String word) {
    count += 1;
    lastText = text;
  }
}

final class _DormantTimer implements Timer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }
}

String _failureDescription(AppFailure failure) {
  return 'code=${failure.code}; '
      'message=${failure.message ?? 'none'}; '
      'cause=${failure.cause ?? 'none'}';
}
