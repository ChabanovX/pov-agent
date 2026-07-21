import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/app/di/assistant_build_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/application/services/first_complete_english_sentence_accumulator.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import '../test/support/assistant_acceptance_durations.dart';

const _runAssistantHardwareSoak = bool.fromEnvironment(
  'RUN_ASSISTANT_HARDWARE_SOAK',
);
const Duration _modelPreparationTimeout = AssistantAcceptanceDurations.modelPreparation;
const Duration _modelReloadTimeout = AssistantAcceptanceDurations.modelReload;
const Duration _runtimeStartTimeout = AssistantAcceptanceDurations.runtimeStart;
const Duration _shortCommentBudget = AssistantAcceptanceDurations.shortComment;
const Duration _streamSettlementTimeout = AssistantAcceptanceDurations.streamSettlement;
const Duration _cancellationTimeout = AssistantAcceptanceDurations.cancellation;
const Duration _stateTransitionTimeout = AssistantAcceptanceDurations.stateTransition;
const Duration _runtimeCloseTimeout = AssistantAcceptanceDurations.runtimeClose;
const Duration _dependencyResetTimeout = AssistantAcceptanceDurations.dependencyReset;
const Duration _widgetDetachTimeout = AssistantAcceptanceDurations.widgetDetach;
const Duration _subscriptionCancelTimeout = AssistantAcceptanceDurations.subscriptionCancel;
const Duration _soakDuration = AssistantAcceptanceDurations.soak;
const Duration _soakProgressInterval = AssistantAcceptanceDurations.soakProgress;
const Duration _memorySampleInterval = AssistantAcceptanceDurations.poll;
const Duration _unloadPollInterval = AssistantAcceptanceDurations.poll;
const Duration _fullScenarioTimeout = AssistantAcceptanceDurations.hardwareScenario;
const Duration _recordedYoloPollInterval = AssistantAcceptanceDurations.poll;
const int _bytesPerMebibyte = 1024 * 1024;
const int _maxRetainedGrowthBytes = 128 * _bytesPerMebibyte;
const int _maxSampledPeakGrowthBytes = 256 * _bytesPerMebibyte;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GPU-backed short comments coexist with YOLO and survive a bounded soak',
    (tester) async {
      final transport = _OfflineGuardDownloader();
      final semantics = tester.ensureSemantics();
      AppRuntime? runtime;
      // Nullable ownership slots let the success path transfer each listener
      // before awaiting, while finally cancels whichever listeners remain.
      // ignore: cancel_subscriptions
      StreamSubscription<CameraState>? cameraSubscription;
      // The model listener uses the same transfer-before-await ownership.
      // ignore: cancel_subscriptions
      StreamSubscription<QwenModelStoreState>? modelSubscription;
      var generationActive = false;
      var qwenPreparationActive = false;
      var latestYoloFrameNumber = 0;
      var yoloFramesDuringQwenPreparation = 0;
      var yoloFramesDuringGeneration = 0;
      final scenarioWatch = Stopwatch()..start();
      Object? scenarioError;
      StackTrace? scenarioStackTrace;

      try {
        tester.printToConsole('IPHONE_ACCEPTANCE stage=initial_runtime_start');
        runtime = configureDependenciesForTesting(
          modelArtifactDownloader: transport,
        );
        modelSubscription = _logModelStoreStates(
          tester,
          runtime,
          scenarioWatch,
          graph: 'initial',
        );
        await runtime.start().timeout(_runtimeStartTimeout);
        await tester.pumpWidget(const PovAgentApp());
        await _pumpUntilRecordedYoloIsVisible(tester);
        latestYoloFrameNumber = runtime.cameraBloc.state.diagnostics?.frameNumber ?? 0;

        cameraSubscription = runtime.cameraBloc.stream.listen((state) {
          final frameNumber = state.diagnostics?.frameNumber;
          if (frameNumber == null || frameNumber <= latestYoloFrameNumber) return;
          latestYoloFrameNumber = frameNumber;
          if (qwenPreparationActive) yoloFramesDuringQwenPreparation += 1;
          if (generationActive) yoloFramesDuringGeneration += 1;
        });

        tester.printToConsole('IPHONE_ACCEPTANCE stage=model_prepare');
        qwenPreparationActive = true;
        runtime.observerBloc.add(const ObserverStarted());
        await tester.pump();
        await _expectModelReady(
          runtime.observerBloc,
          timeout: _modelPreparationTimeout,
          context: 'initial preparation',
        );
        // This legacy lane benchmarks the generator port directly. Disable the
        // eager observer first so its timer cannot contend for the same native
        // single-flight slot and invalidate the latency measurements.
        await _stopAutomaticObservation(runtime.observerBloc);
        qwenPreparationActive = false;
        expect(
          yoloFramesDuringQwenPreparation,
          greaterThan(0),
          reason: 'Recorded YOLO must progress while Qwen loads.',
        );
        final generator = _expectGpuBackedGenerator(runtime.commentGenerator);
        final downloadCallsAtReady = transport.downloadCalls;
        transport.rejectDownloads = true;

        final configuration = AssistantBuildConfiguration.fromEnvironment();
        final promptBuilder = QwenPromptBuilder(
          systemPrompt: configuration.systemPrompt,
          dialogueOptions: configuration.dialogueOptions,
          shortCommentOptions: configuration.commentOptions,
        );

        tester.printToConsole('IPHONE_ACCEPTANCE stage=warmup');
        generationActive = true;
        final warmup = await _generateShortComment(
          generator,
          promptBuilder,
          prompt:
              'Write one short English sentence confirming that '
              'on-device camera analysis is active.',
        );
        generationActive = false;
        _expectValidShortComment(warmup);
        tester.printToConsole(
          'IPHONE_ACCEPTANCE warmup_handle_ms='
          '${warmup.handleAcquisition.inMilliseconds} '
          'warmup_first_chunk_ms='
          '${warmup.firstVisibleChunk.inMilliseconds} '
          'warmup_complete_ms=${warmup.elapsed.inMilliseconds} '
          'rss_mib=${_mebibytes(ProcessInfo.currentRss)}',
        );

        // Take the baseline after model loading and one complete generation so
        // one-time Metal, tokenizer, and KV-cache allocations do not look like
        // a leak. Retained and periodically sampled active-generation limits
        // leave room for native allocator caching while rejecting per-turn
        // growth.
        final baselineRss = ProcessInfo.currentRss;
        expect(
          baselineRss,
          greaterThan(0),
          reason: 'The iOS process must expose resident-memory diagnostics.',
        );
        var sampledPeakRss = baselineRss;
        var completedTurns = 0;
        var slowestComment = Duration.zero;
        final soakWatch = Stopwatch()..start();
        var nextProgress = _soakProgressInterval;
        var yoloFrameAtLastProgress = latestYoloFrameNumber;
        var concurrentFramesAtLastProgress = yoloFramesDuringGeneration;
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=soak_start duration_seconds='
          '${_soakDuration.inSeconds} baseline_rss_mib='
          '${_mebibytes(baselineRss)}',
        );

        while (soakWatch.elapsed < _soakDuration) {
          generationActive = true;
          final measurement = await _generateShortComment(
            generator,
            promptBuilder,
            prompt:
                'Write one short English sentence about a person seen '
                'by an on-device camera. Test turn ${completedTurns + 1}.',
            onMemorySample: (rss) {
              sampledPeakRss = _largerOf(sampledPeakRss, rss);
            },
          );
          generationActive = false;
          _expectValidShortComment(measurement);
          completedTurns += 1;
          if (measurement.elapsed > slowestComment) {
            slowestComment = measurement.elapsed;
          }
          sampledPeakRss = _largerOf(
            sampledPeakRss,
            ProcessInfo.currentRss,
          );

          await tester.pump();
          expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
          expect(runtime.cameraBloc.state.detections, isNotEmpty);

          if (nextProgress < _soakDuration && soakWatch.elapsed >= nextProgress) {
            expect(
              latestYoloFrameNumber,
              greaterThan(yoloFrameAtLastProgress),
              reason: 'YOLO replay must advance during every soak interval.',
            );
            expect(
              yoloFramesDuringGeneration,
              greaterThan(concurrentFramesAtLastProgress),
              reason: 'YOLO and Qwen must overlap during every soak interval.',
            );
            tester.printToConsole(
              'IPHONE_ACCEPTANCE stage=soak_progress '
              'elapsed_seconds=${soakWatch.elapsed.inSeconds} '
              'turns=$completedTurns slowest_comment_ms='
              '${slowestComment.inMilliseconds} rss_mib='
              '${_mebibytes(ProcessInfo.currentRss)} sampled_peak_rss_mib='
              '${_mebibytes(sampledPeakRss)}',
            );
            yoloFrameAtLastProgress = latestYoloFrameNumber;
            concurrentFramesAtLastProgress = yoloFramesDuringGeneration;
            nextProgress += _soakProgressInterval;
          }
        }
        soakWatch.stop();

        expect(
          latestYoloFrameNumber,
          greaterThan(yoloFrameAtLastProgress),
          reason: 'YOLO replay must advance through the final soak interval.',
        );
        expect(
          yoloFramesDuringGeneration,
          greaterThan(concurrentFramesAtLastProgress),
          reason: 'YOLO and Qwen must overlap through the final soak interval.',
        );

        final finalRss = ProcessInfo.currentRss;
        final retainedGrowth = finalRss - baselineRss;
        final sampledPeakGrowth = sampledPeakRss - baselineRss;
        expect(completedTurns, greaterThan(0));
        expect(
          yoloFramesDuringGeneration,
          greaterThan(0),
          reason: 'Recorded YOLO must continue publishing while Qwen decodes.',
        );
        expect(
          generator.generationBusyRejections,
          0,
          reason: 'The direct soak and observer timer must never overlap.',
        );
        expect(
          retainedGrowth,
          lessThanOrEqualTo(_maxRetainedGrowthBytes),
          reason: 'Repeated generations must not retain unbounded memory.',
        );
        expect(
          sampledPeakGrowth,
          lessThanOrEqualTo(_maxSampledPeakGrowthBytes),
          reason: 'Periodic active-generation samples must remain bounded.',
        );
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=soak_complete '
          'elapsed_seconds=${soakWatch.elapsed.inSeconds} '
          'turns=$completedTurns qwen_load_yolo_frames='
          '$yoloFramesDuringQwenPreparation concurrent_yolo_frames='
          '$yoloFramesDuringGeneration slowest_comment_ms='
          '${slowestComment.inMilliseconds} retained_growth_mib='
          '${_mebibytes(retainedGrowth)} sampled_peak_growth_mib='
          '${_mebibytes(sampledPeakGrowth)}',
        );
        final frameBeforeLifecycle = latestYoloFrameNumber;
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=lifecycle_pause_requested',
        );
        _sendApplicationToBackground(tester.binding);
        // A paused physical binding does not owe the test another rendered
        // frame. Await the lifecycle-owned streams directly; pumping here can
        // deadlock after suspension has already completed.
        await _expectModelStatus(
          runtime.observerBloc,
          ObserverModelStatus.suspended,
          timeout: _stateTransitionTimeout,
          context: 'suspend',
        );
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=lifecycle_suspended '
          'camera_status=${runtime.cameraBloc.state.status.name}',
        );
        expect(runtime.cameraBloc.state.status, CameraStatus.disabled);
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=native_unload_wait',
        );
        await _waitForSuccessfulUnload(
          generator,
          timeout: _stateTransitionTimeout,
        );
        expect(generator.loadedModelUsesGpu, isNull);
        tester
          ..printToConsole(
            'IPHONE_ACCEPTANCE stage=native_unload_complete',
          )
          ..printToConsole(
            'IPHONE_ACCEPTANCE stage=lifecycle_resume_requested',
          );
        _sendApplicationToForeground(tester.binding);
        await tester.pump();
        await _expectModelReady(
          runtime.observerBloc,
          timeout: _modelReloadTimeout,
          context: 'foreground reload',
        );
        expect(generator.loadedModelUsesGpu, isTrue);
        expect(transport.downloadCalls, downloadCallsAtReady);
        await _expectYoloAdvancedAfterResume(
          runtime,
          frameBeforeLifecycle,
        );
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=lifecycle_model_ready',
        );
        final reloadedComment = await _generateShortComment(
          generator,
          promptBuilder,
          prompt:
              'Write one short English sentence confirming a '
              'successful foreground reload.',
        );
        _expectValidShortComment(reloadedComment);
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=lifecycle_generation_complete',
        );

        final initialCameraSubscription = cameraSubscription;
        cameraSubscription = null;
        await _cancelSubscription(initialCameraSubscription);
        final initialModelSubscription = modelSubscription;
        modelSubscription = null;
        await _cancelSubscription(initialModelSubscription);
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=initial_graph_subscriptions_cancelled',
        );
        final initialRuntime = runtime;
        runtime = null;
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=initial_runtime_dispose',
        );
        await _disposeRuntime(tester, initialRuntime);

        tester.printToConsole('IPHONE_ACCEPTANCE stage=offline_restart');
        final downloadCallsBeforeRestart = transport.downloadCalls;
        runtime = configureDependenciesForTesting(
          modelArtifactDownloader: transport,
        );
        modelSubscription = _logModelStoreStates(
          tester,
          runtime,
          scenarioWatch,
          graph: 'offline_restart',
        );
        await runtime.start().timeout(_runtimeStartTimeout);
        await tester.pumpWidget(const PovAgentApp());
        await _pumpUntilRecordedYoloIsVisible(tester);
        runtime.observerBloc.add(const ObserverStarted());
        await tester.pump();
        await _expectModelReady(
          runtime.observerBloc,
          timeout: _modelReloadTimeout,
          context: 'offline process-graph restart',
        );
        await _stopAutomaticObservation(runtime.observerBloc);
        final restartedGenerator = _expectGpuBackedGenerator(
          runtime.commentGenerator,
        );
        expect(transport.downloadCalls, downloadCallsBeforeRestart);
        final restartedComment = await _generateShortComment(
          restartedGenerator,
          promptBuilder,
          prompt:
              'Write one short English sentence confirming an offline '
              'restart from the verified model cache.',
        );
        _expectValidShortComment(restartedComment);
        expect(restartedGenerator.generationBusyRejections, 0);
        expect(transport.downloadCalls, downloadCallsBeforeRestart);
        tester.printToConsole(
          'IPHONE_ACCEPTANCE stage=complete offline_restart_ms='
          '${restartedComment.elapsed.inMilliseconds}',
        );
      } on Object catch (error, stackTrace) {
        scenarioError = error;
        scenarioStackTrace = stackTrace;
      } finally {
        generationActive = false;
        Future<void> cleanUp(
          String name,
          Future<void> Function() operation,
        ) async {
          try {
            await operation();
          } on Object catch (error, stackTrace) {
            if (scenarioError == null) {
              scenarioError = error;
              scenarioStackTrace = stackTrace;
            } else {
              tester.printToConsole(
                'IPHONE_ACCEPTANCE cleanup_error=$name error=$error',
              );
            }
          }
        }

        final remainingCameraSubscription = cameraSubscription;
        cameraSubscription = null;
        await cleanUp(
          'camera_subscription',
          () => _cancelSubscription(remainingCameraSubscription),
        );
        final remainingModelSubscription = modelSubscription;
        modelSubscription = null;
        await cleanUp(
          'model_subscription',
          () => _cancelSubscription(remainingModelSubscription),
        );
        if (runtime case final activeRuntime?) {
          runtime = null;
          await cleanUp(
            'runtime_close',
            () => _disposeRuntime(tester, activeRuntime),
          );
        }
        semantics.dispose();
      }

      if (scenarioError case final error?) {
        Error.throwWithStackTrace(error, scenarioStackTrace!);
      }
    },
    skip: !_runAssistantHardwareSoak,
    timeout: const Timeout(_fullScenarioTimeout),
  );
}

void _sendApplicationToBackground(TestWidgetsFlutterBinding binding) {
  binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _sendApplicationToForeground(TestWidgetsFlutterBinding binding) {
  binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

LlamaCommentGenerator _expectGpuBackedGenerator(CommentGenerator generator) {
  expect(generator, isA<LlamaCommentGenerator>());
  final llamaGenerator = generator as LlamaCommentGenerator;
  expect(
    llamaGenerator.loadedModelUsesGpu,
    isTrue,
    reason: 'Physical iOS acceptance requires llama.cpp GPU offload.',
  );
  return llamaGenerator;
}

Future<void> _expectModelReady(
  ObserverBloc bloc, {
  required Duration timeout,
  required String context,
}) async {
  final state = await _waitForObserverState(
    bloc,
    (candidate) =>
        candidate.modelStatus == ObserverModelStatus.ready || candidate.modelStatus == ObserverModelStatus.failure,
    timeout: timeout,
  );
  if (state.modelStatus == ObserverModelStatus.failure) {
    fail(
      'Model $context failed: ${state.modelFailure?.code ?? 'unknown'}; '
      'cause=${state.modelFailure?.cause ?? 'unavailable'}.',
    );
  }
}

Future<void> _expectModelStatus(
  ObserverBloc bloc,
  ObserverModelStatus status, {
  required Duration timeout,
  required String context,
}) async {
  final state = await _waitForObserverState(
    bloc,
    (candidate) => candidate.modelStatus == status,
    timeout: timeout,
  );
  expect(state.modelStatus, status, reason: 'Unexpected $context state.');
}

Future<void> _stopAutomaticObservation(ObserverBloc bloc) async {
  bloc.add(const ObservationStopped());
  final state = await _waitForObserverState(
    bloc,
    (candidate) => !candidate.observationEnabled && candidate.activeGeneration != ObserverGenerationKind.automatic,
    timeout: _stateTransitionTimeout,
  );
  expect(state.activeGeneration, isNull);
}

Future<void> _expectYoloAdvancedAfterResume(
  AppRuntime runtime,
  int frameBeforeLifecycle,
) async {
  bool isAdvanced(CameraState state) {
    final frameNumber = state.diagnostics?.frameNumber;
    return state.status == CameraStatus.enabled &&
        frameNumber != null &&
        frameNumber > frameBeforeLifecycle &&
        state.detections.isNotEmpty;
  }

  final initialState = runtime.cameraBloc.state;
  final resumedState = isAdvanced(initialState)
      ? initialState
      : await runtime.cameraBloc.stream.firstWhere(isAdvanced).timeout(_stateTransitionTimeout);
  expect(resumedState.status, CameraStatus.enabled);
}

Future<ObserverState> _waitForObserverState(
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
}

Future<void> _waitForSuccessfulUnload(
  LlamaCommentGenerator generator, {
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    switch (generator.lastUnloadSucceeded) {
      case true:
        return;
      case false:
        fail('The native assistant model failed to unload.');
      case null:
        await Future<void>.delayed(_unloadPollInterval);
        continue;
    }
  }
  fail(
    'Timed out waiting for successful native assistant unload; '
    'observed ${generator.lastUnloadSucceeded}.',
  );
}

Future<_GenerationMeasurement> _generateShortComment(
  CommentGenerator generator,
  QwenPromptBuilder promptBuilder, {
  required String prompt,
  void Function(int rss)? onMemorySample,
}) async {
  final sampleMemory = onMemorySample;
  sampleMemory?.call(ProcessInfo.currentRss);
  final memoryTimer = sampleMemory == null
      ? null
      : Timer.periodic(_memorySampleInterval, (_) {
          sampleMemory(ProcessInfo.currentRss);
        });
  try {
    return await _generateShortCommentOnce(
      generator,
      promptBuilder,
      prompt: prompt,
    );
  } finally {
    memoryTimer?.cancel();
    sampleMemory?.call(ProcessInfo.currentRss);
  }
}

Future<_GenerationMeasurement> _generateShortCommentOnce(
  CommentGenerator generator,
  QwenPromptBuilder promptBuilder, {
  required String prompt,
}) async {
  final request = promptBuilder.shortComment(prompt: prompt);
  final watch = Stopwatch()..start();
  final startTask = generator.generate(request);
  late final AppResult<GenerationHandle> startResult;
  try {
    startResult = await startTask.timeout(_shortCommentBudget);
  } on TimeoutException {
    // The application port returns ownership only after native prompt prefill.
    // If that boundary finishes late, immediately cancel its otherwise-lost
    // handle while the outer bounded teardown reports the original timeout.
    unawaited(_cancelLateGeneration(startTask));
    rethrow;
  }
  final handle = _successValue(startResult, 'generation start');
  final handleAcquisition = watch.elapsed;
  final streamedAnswer = StringBuffer();
  final chunksDone = Completer<void>();
  Duration? firstVisibleChunk;
  final subscription = handle.chunks.listen(
    (chunk) {
      firstVisibleChunk ??= watch.elapsed;
      streamedAnswer.write(chunk);
    },
    onDone: chunksDone.complete,
  );

  try {
    final remainingBudget = _shortCommentBudget - watch.elapsed;
    if (remainingBudget <= Duration.zero) {
      throw TimeoutException('Generation start exhausted the comment budget.');
    }
    final completion = await handle.completion.timeout(remainingBudget);
    final answer = _successValue(completion, 'generation completion');
    await chunksDone.future.timeout(_streamSettlementTimeout);
    watch.stop();
    final preview = streamedAnswer.toString();
    expect(
      preview,
      contains(answer),
      reason: 'The provisional stream must expose the committed sentence.',
    );
    expect(preview, isNot(contains('<think>')));
    expect(preview, isNot(contains('</think>')));
    expect(
      firstVisibleChunk,
      isNotNull,
      reason: 'A non-empty short comment must cross the streaming boundary.',
    );
    return _GenerationMeasurement(
      answer: answer,
      handleAcquisition: handleAcquisition,
      firstVisibleChunk: firstVisibleChunk!,
      elapsed: watch.elapsed,
    );
  } on TimeoutException {
    await handle.cancel().timeout(_cancellationTimeout, onTimeout: () {});
    rethrow;
  } finally {
    await subscription.cancel();
  }
}

Future<void> _cancelLateGeneration(
  Future<AppResult<GenerationHandle>> startTask,
) async {
  try {
    final result = await startTask;
    if (result case AppSuccess<GenerationHandle>(:final value)) {
      await value.cancel();
    }
  } on Object {
    // The timed-out acceptance operation remains the actionable failure.
  }
}

T _successValue<T>(AppResult<T> result, String operation) {
  return switch (result) {
    AppSuccess<T>(:final value) => value,
    AppError<T>(:final failure) => throw TestFailure(
      '$operation failed: ${failure.code}.',
    ),
  };
}

void _expectValidShortComment(_GenerationMeasurement measurement) {
  final answer = measurement.answer;
  final englishWords = RegExp(
    r"\b[A-Za-z]+(?:['’][A-Za-z]+)?\b",
  ).allMatches(answer);
  final obviousNonLatinScript = RegExp(
    r'[\u0370-\u052F\u0590-\u08FF\u0900-\u097F\u3040-\u30FF'
    r'\u3400-\u9FFF\uAC00-\uD7AF]',
  );
  final completeSentenceEnding = RegExp(
    r'''[.!?]+(?:['"”’»)\]}]*)$''',
  );
  final trimmedAnswer = answer.trim();
  final accumulator = FirstCompleteEnglishSentenceAccumulator();
  final extractedSentence = accumulator.add(trimmedAnswer) ?? accumulator.finish();
  expect(trimmedAnswer, isNotEmpty);
  expect(answer, isNot(contains('<think>')));
  expect(answer, isNot(contains('</think>')));
  expect(answer, isNot(contains('<|')));
  expect(answer, isNot(matches(obviousNonLatinScript)));
  expect(
    englishWords.length,
    greaterThanOrEqualTo(3),
    reason: 'A substantive English sentence must contain at least three words.',
  );
  expect(
    trimmedAnswer,
    matches(completeSentenceEnding),
    reason: 'The short-comment cap must not expose a truncated sentence.',
  );
  expect(
    extractedSentence,
    trimmedAnswer,
    reason:
        'The short-comment output must be exactly one substantive English '
        'sentence; '
        'answer="$trimmedAnswer".',
  );
  expect(
    measurement.elapsed,
    lessThanOrEqualTo(_shortCommentBudget),
    reason: 'A short /no_think comment must complete in under ten seconds.',
  );
}

Future<void> _pumpUntilRecordedYoloIsVisible(WidgetTester tester) async {
  final personDetection = find.semantics.byLabel(RegExp(r'^person \d+%$'));
  for (var attempt = 0; attempt < 600; attempt += 1) {
    await tester.pump(_recordedYoloPollInterval);
    if (personDetection.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for active recorded YOLO inference.');
}

Future<void> _disposeRuntime(WidgetTester tester, AppRuntime runtime) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> attempt(
    String stage,
    Future<void> Function() operation,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    tester.printToConsole(
      'IPHONE_ACCEPTANCE stage=$stage status=start',
    );
    try {
      await operation().timeout(timeout);
      tester.printToConsole(
        'IPHONE_ACCEPTANCE stage=$stage status=complete '
        'elapsed_ms=${watch.elapsedMilliseconds}',
      );
    } on Object catch (error, stackTrace) {
      tester.printToConsole(
        'IPHONE_ACCEPTANCE stage=$stage status=failed '
        'elapsed_ms=${watch.elapsedMilliseconds} error=$error',
      );
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  await attempt(
    'runtime_widget_detach',
    () async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    _widgetDetachTimeout,
  );
  await attempt('runtime_close', runtime.close, _runtimeCloseTimeout);
  await attempt(
    'dependency_reset',
    () => appDependencies.reset(dispose: false),
    _dependencyResetTimeout,
  );

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

Future<void> _cancelSubscription<T>(
  StreamSubscription<T>? subscription,
) async {
  if (subscription == null) return;
  await subscription.cancel().timeout(_subscriptionCancelTimeout);
}

StreamSubscription<QwenModelStoreState> _logModelStoreStates(
  WidgetTester tester,
  AppRuntime runtime,
  Stopwatch watch, {
  required String graph,
}) {
  ModelStorePhase? previousPhase;
  return runtime.modelStore.states.listen((state) {
    if (state.phase == previousPhase) return;
    previousPhase = state.phase;
    tester.printToConsole(
      'IPHONE_ACCEPTANCE model_graph=$graph phase=${state.phase.name} '
      'elapsed_ms=${watch.elapsedMilliseconds}',
    );
  });
}

int _largerOf(int first, int second) => first > second ? first : second;

String _mebibytes(int bytes) {
  return (bytes / _bytesPerMebibyte).toStringAsFixed(1);
}

final class _GenerationMeasurement {
  const _GenerationMeasurement({
    required this.answer,
    required this.handleAcquisition,
    required this.firstVisibleChunk,
    required this.elapsed,
  });

  final String answer;
  final Duration handleAcquisition;
  final Duration firstVisibleChunk;
  final Duration elapsed;
}

final class _OfflineGuardDownloader implements ModelArtifactDownloader {
  final HttpModelArtifactDownloader _delegate = HttpModelArtifactDownloader();

  bool rejectDownloads = false;
  int downloadCalls = 0;

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) {
    downloadCalls += 1;
    if (rejectDownloads) throw const _OfflineTransportException();
    return _delegate.download(
      source: source,
      destinationPath: destinationPath,
      expectedBytes: expectedBytes,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }
}

final class _OfflineTransportException implements Exception {
  const _OfflineTransportException();
}
