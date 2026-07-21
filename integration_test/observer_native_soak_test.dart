import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/ui_constants.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

import '../test/support/assistant_acceptance_durations.dart';

const _runNativeObserverTest = bool.fromEnvironment(
  'RUN_NATIVE_OBSERVER_TEST',
);
const _runLiveObserverTest = bool.fromEnvironment(
  'RUN_LIVE_OBSERVER_TEST',
);
const _requireGpuObserver = bool.fromEnvironment('REQUIRE_GPU_OBSERVER');
const Duration _soakDuration = AssistantAcceptanceDurations.soak;
const Duration _progressInterval = AssistantAcceptanceDurations.soakProgress;
const Duration _modelPreparationTimeout = AssistantAcceptanceDurations.modelPreparation;
const Duration _stateTransitionTimeout = AssistantAcceptanceDurations.stateTransition;
const Duration _runtimeStartTimeout = AssistantAcceptanceDurations.runtimeStart;
const Duration _runtimeCloseTimeout = AssistantAcceptanceDurations.runtimeClose;
const Duration _dependencyResetTimeout = AssistantAcceptanceDurations.dependencyReset;
const Duration _pollInterval = AssistantAcceptanceDurations.poll;
const Duration _scenarioTimeout = AssistantAcceptanceDurations.observerScenario;
const Duration _liveSmokeTimeout = AssistantAcceptanceDurations.observerLiveSmokeScenario;
const Duration _liveSceneTimeout = AssistantAcceptanceDurations.observerLiveScene;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live scene drives a Metal-backed automatic comment and active stop',
    (tester) async {
      final runtime = configureDependencies();
      final semantics = tester.ensureSemantics();
      StreamSubscription<ObserverState>? observerSubscription;
      SceneSnapshot? generatedScene;
      var observedStreaming = false;
      Object? primaryFailure;
      try {
        await _startRuntime(
          tester,
          runtime,
          prefix: 'OBSERVER_LIVE_ACCEPTANCE',
        );
        await tester.pumpWidget(const PovAgentApp());
        await _waitForScene(
          runtime,
          tester,
          timeout: _liveSceneTimeout,
          sourceLabel: 'Live YOLO',
        );
        tester.printToConsole(
          'OBSERVER_LIVE_ACCEPTANCE stage=scene_ready '
          'objects=${runtime.observerBloc.state.scene.objects.length}',
        );
        await _expectModelReady(runtime.observerBloc);

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();
        expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
        expect(find.byKey(observerToggleButtonKey), findsOneWidget);

        final generator = runtime.commentGenerator as LlamaCommentGenerator;
        _printBackendDiagnostic(
          tester,
          generator,
          prefix: 'OBSERVER_LIVE_ACCEPTANCE',
        );
        expect(
          generator.loadedModelUsesGpu,
          isTrue,
          reason: _gpuRequirementFailure(generator),
        );

        // Startup observation may have raced model readiness. Quiesce it and
        // establish the baseline first, then correlate exactly the next
        // sampled live scene with exactly the next committed comment.
        runtime.observerBloc.add(const ObservationStopped());
        await _waitForState(
          runtime.observerBloc,
          (state) => !state.observationEnabled && state.activeGeneration != ObserverGenerationKind.automatic,
          timeout: _stateTransitionTimeout,
        );
        await tester.pump();
        final initialCommentCount = runtime.observerBloc.state.comments.length;
        observerSubscription = runtime.observerBloc.stream.listen((state) {
          if (state.activeGeneration != ObserverGenerationKind.automatic) {
            return;
          }
          generatedScene ??= state.scene;
          if (state.automaticDraft.isNotEmpty) observedStreaming = true;
        });
        await tester.ensureVisible(find.byKey(observerToggleButtonKey));
        await tester.tap(find.byKey(observerToggleButtonKey));
        await _waitForState(
          runtime.observerBloc,
          (state) => state.observationEnabled,
          timeout: _stateTransitionTimeout,
        );

        final completed = await _waitForState(
          runtime.observerBloc,
          (state) => state.comments.length > initialCommentCount || state.automaticFailure != null,
          timeout: _liveSceneTimeout,
        );
        if (completed.automaticFailure case final failure?) {
          fail(
            'The first live automatic generation failed: '
            'code=${failure.code}; '
            'message=${failure.message ?? 'none'}; '
            'cause=${failure.cause ?? 'none'}.',
          );
        }
        final comment = completed.comments.last;
        expect(observedStreaming, isTrue);
        expect(generatedScene, isNotNull);
        expect(generatedScene!.isNotEmpty, isTrue);
        expect(comment.scene, generatedScene);
        expect(comment.text.trim(), isNotEmpty);
        expect(completed.automaticFailure, isNull);
        expect(generator.generationBusyRejections, 0);

        // Cancel only after native decoding has published a visible prefix.
        // This proves stop waits for an active live-camera generation rather
        // than merely disabling an idle timer between comments.
        final active = await _waitForState(
          runtime.observerBloc,
          (state) =>
              state.automaticFailure != null ||
              state.activeGeneration == ObserverGenerationKind.automatic && state.automaticDraft.isNotEmpty,
          timeout: _liveSceneTimeout,
        );
        if (active.automaticFailure case final failure?) {
          fail(
            'The cancellable live automatic generation failed before stop: '
            'code=${failure.code}; '
            'message=${failure.message ?? 'none'}; '
            'cause=${failure.cause ?? 'none'}.',
          );
        }
        final commentsAtStop = active.comments.length;
        runtime.observerBloc.add(const ObservationStopped());
        await _waitForState(
          runtime.observerBloc,
          (state) => !state.observationEnabled && state.activeGeneration != ObserverGenerationKind.automatic,
          timeout: _stateTransitionTimeout,
        );
        await Future<void>.delayed(
          AssistantAcceptanceDurations.observerStopSilence,
        );
        await tester.pump();
        expect(runtime.observerBloc.state.comments, hasLength(commentsAtStop));
        expect(generator.generationBusyRejections, 0);

        tester.printToConsole(
          'OBSERVER_LIVE_ACCEPTANCE stage=complete '
          'objects=${comment.scene.objects.length} '
          'comment=${comment.text}',
        );
      } on Object catch (error) {
        primaryFailure = error;
        rethrow;
      } finally {
        await observerSubscription?.cancel();
        semantics.dispose();
        try {
          await _disposeRuntime(tester, runtime);
        } on Object catch (error) {
          if (primaryFailure == null) rethrow;
          tester.printToConsole(
            'OBSERVER_LIVE_ACCEPTANCE stage=cleanup_failure '
            'error=${_singleLine('$error')}',
          );
        }
      }
    },
    skip: !_runLiveObserverTest,
    timeout: const Timeout(_liveSmokeTimeout),
  );

  testWidgets(
    'stable scene drives the automatic observer for ten minutes',
    (tester) async {
      final runtime = configureDependencies();
      final semantics = tester.ensureSemantics();
      StreamSubscription<ObserverState>? observerSubscription;
      Object? primaryFailure;
      try {
        await _startRuntime(
          tester,
          runtime,
          prefix: 'OBSERVER_ACCEPTANCE',
        );
        await tester.pumpWidget(const PovAgentApp());
        await _waitForScene(
          runtime,
          tester,
          timeout: _stateTransitionTimeout,
          sourceLabel: 'Recorded YOLO',
        );
        tester.printToConsole(
          'OBSERVER_ACCEPTANCE stage=scene_ready '
          'objects=${runtime.observerBloc.state.scene.objects.length}',
        );
        await _expectModelReady(runtime.observerBloc);

        await tester.tap(find.text('Assistant'));
        await tester.pumpAndSettle();
        expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
        expect(runtime.observerBloc.state.scene.isNotEmpty, isTrue);
        expect(find.byKey(observerToggleButtonKey), findsOneWidget);
        expect(find.text('Watching every 10 seconds'), findsOneWidget);

        final generator = runtime.commentGenerator as LlamaCommentGenerator;
        _printBackendDiagnostic(
          tester,
          generator,
          prefix: 'OBSERVER_ACCEPTANCE',
        );
        if (_requireGpuObserver) {
          expect(
            generator.loadedModelUsesGpu,
            isTrue,
            reason: _gpuRequirementFailure(generator),
          );
        }

        // Preparation and the first timer tick can overlap before the soak
        // subscribes. Quiesce that startup window so every measured failure,
        // comment, and latency belongs to this exact ten-minute session.
        runtime.observerBloc.add(const ObservationStopped());
        await _waitForState(
          runtime.observerBloc,
          (state) => !state.observationEnabled && state.activeGeneration != ObserverGenerationKind.automatic,
          timeout: _stateTransitionTimeout,
        );
        await tester.pump();
        expect(runtime.observerBloc.state.automaticFailure, isNull);

        var automaticWasActive = false;
        Stopwatch? automaticWatch;
        Duration? automaticFirstDraft;
        var latestAutomaticDraft = '';
        var slowestComment = Duration.zero;
        var observedStreaming = false;
        var automaticFailureVisible = false;
        final automaticFailureCodes = <String>[];
        var completedDuringSoak = 0;
        var previousCommentCount = runtime.observerBloc.state.comments.length;
        observerSubscription = runtime.observerBloc.stream.listen((state) {
          final nowAutomatic = state.activeGeneration == ObserverGenerationKind.automatic;
          if (nowAutomatic && !automaticWasActive) {
            automaticWatch = Stopwatch()..start();
            automaticFirstDraft = null;
            latestAutomaticDraft = '';
          }
          if (nowAutomatic && state.automaticDraft.isNotEmpty) {
            observedStreaming = true;
            automaticFirstDraft ??= automaticWatch?.elapsed;
            latestAutomaticDraft = state.automaticDraft;
          }
          final automaticFailure = state.automaticFailure;
          if (automaticFailure != null && !automaticFailureVisible) {
            automaticFailureCodes.add(automaticFailure.code);
            tester.printToConsole(
              'OBSERVER_ACCEPTANCE stage=automatic_failure '
              'code=${automaticFailure.code} '
              'message=${automaticFailure.message ?? 'none'} '
              'cause=${automaticFailure.cause ?? 'none'} '
              'latency_ms=${automaticWatch?.elapsedMilliseconds ?? -1} '
              'draft=${_singleLine(latestAutomaticDraft)}',
            );
          }
          automaticFailureVisible = automaticFailure != null;
          if (state.comments.length > previousCommentCount) {
            completedDuringSoak += state.comments.length - previousCommentCount;
            previousCommentCount = state.comments.length;
            automaticWatch?.stop();
            if (automaticWatch case final watch?) {
              if (watch.elapsed > slowestComment) {
                slowestComment = watch.elapsed;
                final text = state.comments.last.text.trim();
                final wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
                tester.printToConsole(
                  'OBSERVER_ACCEPTANCE stage=slowest_comment '
                  'comment=$completedDuringSoak '
                  'latency_ms=${slowestComment.inMilliseconds} '
                  'first_draft_ms=${automaticFirstDraft?.inMilliseconds ?? -1} '
                  'words=$wordCount text=${_singleLine(text)}',
                );
              }
            }
            automaticWatch = null;
            automaticFirstDraft = null;
            latestAutomaticDraft = '';
          }
          automaticWasActive = nowAutomatic;
        });

        await tester.ensureVisible(find.byKey(observerToggleButtonKey));
        await tester.tap(find.byKey(observerToggleButtonKey));
        await _waitForState(
          runtime.observerBloc,
          (state) => state.observationEnabled,
          timeout: _stateTransitionTimeout,
        );

        final baselineRss = ProcessInfo.currentRss;
        var sampledPeakRss = baselineRss;
        var lastFrame = runtime.cameraBloc.state.diagnostics?.frameNumber ?? 0;
        final soakWatch = Stopwatch()..start();
        var nextProgress = _progressInterval;
        tester.printToConsole(
          'OBSERVER_ACCEPTANCE stage=soak_start '
          'duration_seconds=${_soakDuration.inSeconds} '
          'baseline_rss_mib=${_mebibytes(baselineRss)}',
        );

        while (soakWatch.elapsed < _soakDuration) {
          await Future<void>.delayed(_pollInterval);
          await tester.pump();
          sampledPeakRss = _largerOf(sampledPeakRss, ProcessInfo.currentRss);

          if (soakWatch.elapsed >= nextProgress) {
            final frame = runtime.cameraBloc.state.diagnostics?.frameNumber ?? 0;
            expect(
              frame,
              greaterThan(lastFrame),
              reason: 'Recorded YOLO must advance during every soak minute.',
            );
            expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
            expect(runtime.observerBloc.state.scene.isNotEmpty, isTrue);
            tester.printToConsole(
              'OBSERVER_ACCEPTANCE stage=soak_progress '
              'elapsed_seconds=${soakWatch.elapsed.inSeconds} '
              'comments=$completedDuringSoak frame=$frame '
              'rss_mib=${_mebibytes(ProcessInfo.currentRss)}',
            );
            lastFrame = frame;
            nextProgress += _progressInterval;
          }
        }
        soakWatch.stop();

        expect(generator.generationBusyRejections, 0);
        expect(
          automaticFailureCodes,
          isEmpty,
          reason:
              'Automatic generations failed during the measured soak: '
              '${automaticFailureCodes.join(', ')}.',
        );
        expect(observedStreaming, isTrue);
        if (_requireGpuObserver) {
          expect(
            slowestComment,
            lessThanOrEqualTo(AssistantAcceptanceDurations.shortComment),
          );
        }
        expect(
          completedDuringSoak,
          greaterThanOrEqualTo(20),
          reason: 'The ten-second observer should complete repeated comments.',
        );
        expect(
          runtime.observerBloc.state.comments.every(
            (comment) => comment.scene.isNotEmpty && comment.text.trim().isNotEmpty,
          ),
          isTrue,
        );

        await _waitForState(
          runtime.observerBloc,
          (state) => state.activeGeneration == ObserverGenerationKind.automatic,
          timeout: AssistantAcceptanceDurations.observerTickWait,
        );
        await tester.ensureVisible(find.byKey(observerToggleButtonKey));
        await tester.tap(find.byKey(observerToggleButtonKey));
        final stopped = await _waitForState(
          runtime.observerBloc,
          (state) => !state.observationEnabled && state.activeGeneration != ObserverGenerationKind.automatic,
          timeout: _stateTransitionTimeout,
        );
        final commentsAtStop = stopped.comments.length;
        await Future<void>.delayed(
          AssistantAcceptanceDurations.observerStopSilence,
        );
        await tester.pump();
        expect(runtime.observerBloc.state.comments, hasLength(commentsAtStop));
        expect(find.text('Automatic observation is stopped.'), findsOneWidget);

        tester.printToConsole(
          'OBSERVER_ACCEPTANCE stage=complete '
          'elapsed_seconds=${soakWatch.elapsed.inSeconds} '
          'comments=$completedDuringSoak '
          'slowest_comment_ms=${slowestComment.inMilliseconds} '
          'sampled_peak_growth_mib='
          '${_mebibytes(sampledPeakRss - baselineRss)}',
        );
      } on Object catch (error) {
        primaryFailure = error;
        rethrow;
      } finally {
        await observerSubscription?.cancel();
        semantics.dispose();
        try {
          await _disposeRuntime(tester, runtime);
        } on Object catch (error) {
          if (primaryFailure == null) rethrow;
          tester.printToConsole(
            'OBSERVER_ACCEPTANCE stage=cleanup_failure '
            'error=${_singleLine('$error')}',
          );
        }
      }
    },
    skip: !_runNativeObserverTest,
    timeout: const Timeout(_scenarioTimeout),
  );
}

Future<void> _startRuntime(
  WidgetTester tester,
  AppRuntime runtime, {
  required String prefix,
}) async {
  tester.printToConsole('$prefix stage=runtime_start');
  try {
    await runtime.start().timeout(_runtimeStartTimeout);
  } on TimeoutException {
    final cameraState = runtime.cameraBloc.state;
    final failure = cameraState.failure;
    fail(
      'Runtime startup timed out: '
      'camera_status=${cameraState.status.name}; '
      'camera_model_status=${cameraState.modelStatus.name}; '
      'camera_failure=${failure?.code ?? 'none'}; '
      'observer_started=${runtime.observerBloc.state.started}; '
      'observer_model_status=${runtime.observerBloc.state.modelStatus.name}.',
    );
  }
  tester.printToConsole(
    '$prefix stage=runtime_ready '
    'camera_status=${runtime.cameraBloc.state.status.name} '
    'observer_started=${runtime.observerBloc.state.started}',
  );
}

Future<void> _waitForScene(
  AppRuntime runtime,
  WidgetTester tester, {
  required Duration timeout,
  required String sourceLabel,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(_pollInterval);
    if (runtime.cameraBloc.state.status == CameraStatus.enabled && runtime.observerBloc.state.scene.isNotEmpty) {
      return;
    }
  }
  fail('$sourceLabel did not publish a stable scene.');
}

Future<void> _expectModelReady(ObserverBloc bloc) async {
  final state = await _waitForState(
    bloc,
    (candidate) =>
        candidate.modelStatus == ObserverModelStatus.ready || candidate.modelStatus == ObserverModelStatus.failure,
    timeout: _modelPreparationTimeout,
  );
  if (state.modelStatus == ObserverModelStatus.failure) {
    final failure = state.modelFailure;
    fail(
      'Observer model preparation failed: '
      '${failure?.code ?? 'unknown'}; '
      'message=${failure?.message ?? 'none'}; '
      'cause=${failure?.cause ?? 'none'}.',
    );
  }
}

Future<ObserverState> _waitForState(
  ObserverBloc bloc,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
}

void _printBackendDiagnostic(
  WidgetTester tester,
  LlamaCommentGenerator generator, {
  required String prefix,
}) {
  final diagnostic = generator.loadedModelBackendDiagnostic;
  tester.printToConsole(
    '$prefix stage=model_backend '
    'uses_gpu=${generator.loadedModelUsesGpu} '
    'diagnostic=${diagnostic == null ? 'none' : _singleLine(diagnostic)}',
  );
}

String _gpuRequirementFailure(LlamaCommentGenerator generator) {
  return 'Physical iOS acceptance requires actual Metal model offload. '
      'Native diagnostic: '
      '${generator.loadedModelBackendDiagnostic ?? 'none'}';
}

String _singleLine(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Future<void> _disposeRuntime(
  WidgetTester tester,
  AppRuntime runtime,
) async {
  await tester.pumpWidget(const SizedBox.shrink()).timeout(_stateTransitionTimeout);
  await tester.pump();
  await runtime.close().timeout(_runtimeCloseTimeout);
  await appDependencies.reset(dispose: false).timeout(_dependencyResetTimeout);
}

int _largerOf(int left, int right) => left > right ? left : right;

String _mebibytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
