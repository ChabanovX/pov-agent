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
import 'package:pov_agent/features/assistant/data/adapters/just_audio_generated_speech_player.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_piper_model_store.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_state.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import '../test/support/assistant_acceptance_durations.dart';

const _runNativePiperTest = bool.fromEnvironment('RUN_NATIVE_PIPER_TEST');
const _interruptedUtterance =
    'A person is walking through a bright room while the local observer keeps '
    'watching the recorded scene and calmly describes the changing light, the '
    'nearby furniture, the movement across the camera, and the details in the '
    'background so this deliberately long single sentence keeps native audio '
    'playing long enough for another recorded detection to finish and for the '
    'acceptance test to interrupt playback before the complete sentence can '
    'reach its natural end.';
const _replayUtterance = 'Local Piper speech replayed successfully.';
const _offlineUtterance = 'Local Piper speech works from the verified offline cache.';

const Duration _speechTimeout = AssistantAcceptanceDurations.modelPreparation;
const Duration _playbackStartTimeout = AssistantAcceptanceDurations.modelPreparation;
const Duration _fullScenarioTimeout = AssistantAcceptanceDurations.hardwareScenario;
const Duration _pollInterval = AssistantAcceptanceDurations.poll;
const Duration _nativeProbePollInterval = AssistantAcceptanceDurations.nativeProbePoll;

// Native scenario matrix:
// - Cold Piper acquisition while recorded YOLO and loaded Qwen stay active.
// - Playback interruption, same-graph replay, then transport-disabled restart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Piper cold acquisition, stop/replay, and offline restart stay native',
    (tester) async {
      if (!Platform.isIOS && !Platform.isAndroid) {
        fail(
          'Piper native acceptance supports only iOS and Android, not '
          '${Platform.operatingSystem}.',
        );
      }

      await appDependencies.reset(dispose: false);
      await _removePinnedPiperCache();

      final qwenTransport = _OfflineGuardDownloader();
      final piperTransport = _OfflineGuardDownloader();
      final semantics = tester.ensureSemantics();
      AppRuntime? activeRuntime;
      Object? scenarioError;
      StackTrace? scenarioStackTrace;

      try {
        final runtime = configureDependenciesForTesting(
          modelArtifactDownloader: qwenTransport,
          piperModelArtifactDownloader: piperTransport,
        );
        activeRuntime = runtime;
        final piper = appDependencies<PiperSpeechSynthesizer>();
        final player = appDependencies<JustAudioGeneratedSpeechPlayer>();
        final piperStore = appDependencies<VerifiedPiperModelStore>();
        final coldPhases = <ModelStorePhase>[];
        final coldStateSubscription = piperStore.states.listen(
          (state) => coldPhases.add(state.phase),
        );

        try {
          await _startRecordedGraph(tester, runtime);
          final qwen = runtime.commentGenerator as LlamaCommentGenerator;
          expect(
            qwen.loadedModelUsesGpu,
            isNotNull,
            reason: 'Observer readiness must include a loaded Qwen runtime.',
          );
          final frameBeforePiper = runtime.cameraBloc.state.diagnostics?.frameNumber;
          expect(
            frameBeforePiper,
            isNotNull,
            reason: 'Recorded YOLO must publish diagnostics before Piper starts.',
          );

          final startedBeforeInterrupt = player.playbackProbe.startedCount;
          final interruptedSpeech = runtime.speechSynthesizer.speak(
            _interruptedUtterance,
          );
          final synthesisFrames = await _waitForConcurrentYoloInference(
            operation: interruptedSpeech,
            runtime: runtime,
            piper: piper,
            player: player,
            qwen: qwen,
            frameBeforePiper: frameBeforePiper!,
            timeout: _playbackStartTimeout,
          );
          final playbackObservedAt = await _waitForPlaybackStart(
            operation: interruptedSpeech,
            piper: piper,
            player: player,
            startedAfter: startedBeforeInterrupt,
            timeout: _playbackStartTimeout,
          );
          _expectYoloSampleInsideNativeRuntime(
            piper: piper,
            sampledAt: synthesisFrames.concurrentSampledAt,
          );
          final frameAtPlaybackStart =
              runtime.cameraBloc.state.diagnostics?.frameNumber ?? synthesisFrames.concurrentFrame;
          final frameDuringPlayback = await _waitForYoloFrameDuringPlayback(
            runtime: runtime,
            player: player,
            previousFrame: frameAtPlaybackStart,
            stageStartedAt: playbackObservedAt,
            timeout: AssistantAcceptanceDurations.stateTransition,
          );

          expect(piper.nativeRuntimeActive, isFalse);
          expect(piper.synthesisAttempts, 1);
          expect(piper.synthesisSettlements, 1);
          expect(piper.lastSampleCount, greaterThan(0));
          expect(piper.lastSampleRateHz, 22050);
          expect(piper.lastPeakAmplitude, greaterThan(0));
          expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
          expect(
            find.semantics.byLabel(RegExp(r'^person \d+%$')),
            findsAtLeast(1),
          );
          expect(qwen.loadedModelUsesGpu, isNotNull);

          _expectSuccess(
            await runtime.speechSynthesizer.stop().timeout(_speechTimeout),
            stage: 'interrupt',
          );
          _expectSuccess(
            await interruptedSpeech.timeout(_speechTimeout),
            stage: 'interrupted settlement',
          );
          expect(player.playbackProbe.isPlaying, isFalse);
          expect(player.playbackProbe.stoppedCount, 1);
          expect(piper.completedPlaybacks, 0);

          final downloadsAfterColdPrepare = piperTransport.downloadCalls;
          expect(
            downloadsAfterColdPrepare,
            1,
            reason: 'The cleared Piper cache must exercise one real download.',
          );
          expect(
            piperTransport.sources.single,
            AssistantBuildConfiguration.fromEnvironment().piperManifest.downloadUri,
          );
          expect(coldPhases, contains(ModelStorePhase.downloading));
          expect(coldPhases, contains(ModelStorePhase.verifying));
          expect(coldPhases, contains(ModelStorePhase.ready));

          _expectSuccess(
            await runtime.speechSynthesizer
                .speak(_replayUtterance)
                .timeout(
                  _speechTimeout,
                ),
            stage: 'same-graph replay',
          );
          expect(piperTransport.downloadCalls, downloadsAfterColdPrepare);
          expect(piper.synthesisAttempts, 2);
          expect(piper.synthesisSettlements, 2);
          expect(piper.completedPlaybacks, 1);
          expect(player.playbackProbe.startedCount, 2);
          expect(player.playbackProbe.completedCount, 1);
          expect(player.playbackProbe.failedCount, 0);
          await _verifyObserverDrivenSpeech(
            runtime: runtime,
            piper: piper,
            player: player,
          );
          expect(piper.synthesisAttempts, 3);
          expect(piper.synthesisSettlements, 3);
          expect(piper.completedPlaybacks, 2);
          expect(player.playbackProbe.startedCount, 3);
          expect(player.playbackProbe.completedCount, 2);
          expect(player.playbackProbe.failedCount, 0);
          tester.printToConsole(
            'PIPER_NATIVE_ACCEPTANCE stage=cold_replay_complete '
            'platform=${Platform.operatingSystem} '
            'downloads=${piperTransport.downloadCalls} '
            'samples=${piper.lastSampleCount} '
            'sample_rate=${piper.lastSampleRateHz} '
            'peak=${piper.lastPeakAmplitude} '
            'yolo_frames=$frameBeforePiper->'
            '${synthesisFrames.synthesisStartFrame}->'
            '${synthesisFrames.concurrentFrame}->'
            '$frameAtPlaybackStart->$frameDuringPlayback',
          );
        } finally {
          await coldStateSubscription.cancel();
        }

        await _disposeRuntime(tester, runtime);
        activeRuntime = null;

        qwenTransport.rejectDownloads = true;
        piperTransport.rejectDownloads = true;
        final qwenDownloadsBeforeOfflineGraph = qwenTransport.downloadCalls;
        final piperDownloadsBeforeOfflineGraph = piperTransport.downloadCalls;

        final offlineRuntime = configureDependenciesForTesting(
          modelArtifactDownloader: qwenTransport,
          piperModelArtifactDownloader: piperTransport,
        );
        activeRuntime = offlineRuntime;
        final offlinePiper = appDependencies<PiperSpeechSynthesizer>();
        final offlinePlayer = appDependencies<JustAudioGeneratedSpeechPlayer>();
        final offlineStore = appDependencies<VerifiedPiperModelStore>();
        final offlinePhases = <ModelStorePhase>[];
        final offlineStateSubscription = offlineStore.states.listen(
          (state) => offlinePhases.add(state.phase),
        );

        try {
          await _startRecordedGraph(tester, offlineRuntime);
          expect(
            (offlineRuntime.commentGenerator as LlamaCommentGenerator).loadedModelUsesGpu,
            isNotNull,
          );
          _expectSuccess(
            await offlineRuntime.speechSynthesizer
                .speak(_offlineUtterance)
                .timeout(
                  _speechTimeout,
                ),
            stage: 'transport-disabled restart',
          );

          expect(qwenTransport.downloadCalls, qwenDownloadsBeforeOfflineGraph);
          expect(piperTransport.downloadCalls, piperDownloadsBeforeOfflineGraph);
          expect(offlinePhases, isNot(contains(ModelStorePhase.downloading)));
          expect(offlinePhases, contains(ModelStorePhase.verifying));
          expect(offlinePhases, contains(ModelStorePhase.ready));
          expect(offlinePiper.nativeRuntimeActive, isFalse);
          expect(offlinePiper.synthesisAttempts, 1);
          expect(offlinePiper.synthesisSettlements, 1);
          expect(offlinePiper.completedPlaybacks, 1);
          expect(offlinePlayer.playbackProbe.startedCount, 1);
          expect(offlinePlayer.playbackProbe.completedCount, 1);
          expect(offlinePlayer.playbackProbe.failedCount, 0);
          tester.printToConsole(
            'PIPER_NATIVE_ACCEPTANCE stage=offline_restart_complete '
            'platform=${Platform.operatingSystem} '
            'piper_downloads=${piperTransport.downloadCalls} '
            'qwen_downloads=${qwenTransport.downloadCalls}',
          );
        } finally {
          await offlineStateSubscription.cancel();
        }

        await _disposeRuntime(tester, offlineRuntime);
        activeRuntime = null;
      } on Object catch (error, stackTrace) {
        scenarioError = error;
        scenarioStackTrace = stackTrace;
      }

      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      try {
        await _cleanupAcceptanceResources(
          tester: tester,
          semantics: semantics,
          activeRuntime: activeRuntime,
        );
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }

      final primaryError = scenarioError;
      if (primaryError != null) {
        final secondaryError = cleanupError;
        if (secondaryError != null) {
          Error.throwWithStackTrace(
            _ScenarioAndCleanupFailure(primaryError, secondaryError),
            scenarioStackTrace!,
          );
        }
        Error.throwWithStackTrace(primaryError, scenarioStackTrace!);
      }
      if (cleanupError case final error?) {
        Error.throwWithStackTrace(error, cleanupStackTrace!);
      }
    },
    skip: !_runNativePiperTest,
    timeout: const Timeout(_fullScenarioTimeout),
  );
}

Future<void> _verifyObserverDrivenSpeech({
  required AppRuntime runtime,
  required PiperSpeechSynthesizer piper,
  required JustAudioGeneratedSpeechPlayer player,
}) async {
  final bloc = runtime.observerBloc;
  final commentsBefore = bloc.state.comments.length;
  final attemptsBefore = piper.synthesisAttempts;
  final completedBefore = piper.completedPlaybacks;
  final playbackStartedBefore = player.playbackProbe.startedCount;
  final playbackCompletedBefore = player.playbackProbe.completedCount;

  bloc.add(const ObserverSpeechMutedChanged(muted: false));
  await _waitForState(
    runtime,
    (state) => !state.speechMuted,
    timeout: AssistantAcceptanceDurations.stateTransition,
  );
  bloc.add(const ObservationStarted());
  await _waitForState(
    runtime,
    (state) => state.observationEnabled,
    timeout: AssistantAcceptanceDurations.stateTransition,
  );

  final outcome = await _waitForState(
    runtime,
    (state) =>
        state.automaticFailure != null ||
        state.speechFailure != null ||
        (state.comments.length > commentsBefore && piper.completedPlaybacks > completedBefore && !state.isSpeaking),
    timeout: _speechTimeout,
  );
  if (outcome.automaticFailure case final failure?) {
    fail(
      'Observer-driven Qwen comment failed before Piper speech: '
      '${_failureDescription(failure)}.',
    );
  }
  if (outcome.speechFailure case final failure?) {
    fail(
      'Observer-driven Piper speech failed: '
      '${_failureDescription(failure)}.',
    );
  }

  expect(outcome.comments.length, greaterThan(commentsBefore));
  expect(piper.synthesisAttempts, attemptsBefore + 1);
  expect(piper.completedPlaybacks, completedBefore + 1);
  expect(player.playbackProbe.startedCount, playbackStartedBefore + 1);
  expect(player.playbackProbe.completedCount, playbackCompletedBefore + 1);
  await _quiesceAutomaticSpeech(runtime);
}

Future<void> _cleanupAcceptanceResources({
  required WidgetTester tester,
  required SemanticsHandle semantics,
  required AppRuntime? activeRuntime,
}) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  try {
    semantics.dispose();
  } on Object catch (error, stackTrace) {
    firstError = error;
    firstStackTrace = stackTrace;
  }

  try {
    final runtime = activeRuntime;
    if (runtime != null) {
      await _disposeRuntime(tester, runtime);
    } else {
      await appDependencies.reset(dispose: false);
    }
  } on Object catch (error, stackTrace) {
    firstError ??= error;
    firstStackTrace ??= stackTrace;
  }

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

Future<void> _startRecordedGraph(
  WidgetTester tester,
  AppRuntime runtime,
) async {
  await runtime.start().timeout(AssistantAcceptanceDurations.runtimeStart);
  await _quiesceAutomaticSpeech(runtime);
  await tester.pumpWidget(const PovAgentApp());
  await _pumpUntilFound(tester, find.bySemanticsLabel('Disable camera'));
  final personDetection = find.semantics.byLabel(RegExp(r'^person \d+%$'));
  await _pumpUntilFound(tester, personDetection);

  final readyState = await _waitForState(
    runtime,
    (state) => state.modelStatus == ObserverModelStatus.ready || state.modelStatus == ObserverModelStatus.failure,
    timeout: AssistantAcceptanceDurations.modelPreparation,
  );
  if (readyState.modelStatus == ObserverModelStatus.failure) {
    fail(
      'Qwen preparation failed while starting Piper acceptance: '
      '${_failureDescription(readyState.modelFailure)}.',
    );
  }
  expect(runtime.cameraBloc.state.status, CameraStatus.enabled);
  expect(personDetection, findsAtLeast(1));
}

Future<void> _quiesceAutomaticSpeech(AppRuntime runtime) async {
  final bloc = runtime.observerBloc..add(const ObservationStopped());
  await _waitForState(
    runtime,
    (state) => !state.observationEnabled && state.activeGeneration != ObserverGenerationKind.automatic,
    timeout: AssistantAcceptanceDurations.stateTransition,
  );

  bloc.add(const ObserverSpeechMutedChanged(muted: true));
  await _waitForState(
    runtime,
    (state) => state.speechMuted && !state.isSpeaking,
    timeout: AssistantAcceptanceDurations.stateTransition,
  );
  _expectSuccess(
    await runtime.speechSynthesizer.stop().timeout(
      AssistantAcceptanceDurations.stateTransition,
    ),
    stage: 'automatic speech quiescence',
  );
}

Future<ObserverState> _waitForState(
  AppRuntime runtime,
  bool Function(ObserverState state) predicate, {
  required Duration timeout,
}) {
  final bloc = runtime.observerBloc;
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate).timeout(timeout);
}

Future<int> _waitForYoloFrameDuringPlayback({
  required AppRuntime runtime,
  required JustAudioGeneratedSpeechPlayer player,
  required int previousFrame,
  required DateTime stageStartedAt,
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (!player.playbackProbe.isPlaying) {
      fail(
        'Native Piper playback ended before recorded YOLO advanced: '
        'frame=$previousFrame.',
      );
    }
    final diagnostics = runtime.cameraBloc.state.diagnostics;
    if (diagnostics != null &&
        diagnostics.frameNumber > previousFrame &&
        diagnostics.sampledAt.isAfter(stageStartedAt)) {
      return diagnostics.frameNumber;
    }
    await Future<void>.delayed(_nativeProbePollInterval);
  }
  fail(
    'Timed out waiting for recorded YOLO to advance during native playback: '
    'frame=$previousFrame.',
  );
}

Future<
  ({
    int synthesisStartFrame,
    int concurrentFrame,
    DateTime concurrentSampledAt,
  })
>
_waitForConcurrentYoloInference({
  required Future<AppResult<void>> operation,
  required AppRuntime runtime,
  required PiperSpeechSynthesizer piper,
  required JustAudioGeneratedSpeechPlayer player,
  required LlamaCommentGenerator qwen,
  required int frameBeforePiper,
  required Duration timeout,
}) async {
  AppResult<void>? settledResult;
  Object? unexpectedError;
  var settled = false;
  var observedSynthesis = false;
  int? synthesisStartFrame;
  DateTime? synthesisObservedAt;
  unawaited(
    operation.then<void>(
      (result) {
        settledResult = result;
        settled = true;
      },
      onError: (Object error, StackTrace _) {
        unexpectedError = error;
        settled = true;
      },
    ),
  );

  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (piper.nativeRuntimeActive) {
      final diagnostics = runtime.cameraBloc.state.diagnostics;
      if (!observedSynthesis) {
        observedSynthesis = true;
        synthesisStartFrame = diagnostics?.frameNumber ?? frameBeforePiper;
        synthesisObservedAt = DateTime.now().toUtc();
      }
      if (qwen.loadedModelUsesGpu == null) {
        fail('Qwen unloaded while Piper owned its native synthesis runtime.');
      }
      if (diagnostics != null &&
          diagnostics.frameNumber > synthesisStartFrame! &&
          diagnostics.sampledAt.isAfter(synthesisObservedAt!)) {
        return (
          synthesisStartFrame: synthesisStartFrame,
          concurrentFrame: diagnostics.frameNumber,
          concurrentSampledAt: diagnostics.sampledAt,
        );
      }
    } else if (observedSynthesis) {
      fail(
        'Piper synthesis settled before recorded YOLO published another frame: '
        'frame=$synthesisStartFrame.',
      );
    }

    if (settled) {
      final result = settledResult;
      if (result case AppError<void>(:final failure)) {
        fail(
          'Piper speech failed before concurrent inference was observed: '
          '${_failureDescription(failure)}.',
        );
      }
      fail(
        'Piper speech settled before concurrent inference was observed: '
        '${unexpectedError ?? 'successful early completion'}; '
        '${_nativeSpeechDiagnostics(piper, player)}.',
      );
    }
    await Future<void>.delayed(_nativeProbePollInterval);
  }
  fail(
    'Timed out waiting for recorded YOLO to advance during Piper synthesis: '
    'frame_before=$frameBeforePiper; synthesis_seen=$observedSynthesis.',
  );
}

void _expectYoloSampleInsideNativeRuntime({
  required PiperSpeechSynthesizer piper,
  required DateTime sampledAt,
}) {
  final createdAt = piper.lastNativeRuntimeCreatedAtUtc;
  final freedAt = piper.lastNativeRuntimeFreedAtUtc;
  expect(
    createdAt,
    isNotNull,
    reason: 'The sherpa worker must report successful OfflineTts creation.',
  );
  expect(
    freedAt,
    isNotNull,
    reason: 'The sherpa worker must report OfflineTts.free() completion.',
  );
  if (sampledAt.isBefore(createdAt!) || sampledAt.isAfter(freedAt!)) {
    fail(
      'Recorded YOLO did not complete inside exact native Piper ownership: '
      'sampled_at=$sampledAt, created_at=$createdAt, freed_at=$freedAt.',
    );
  }
}

String _nativeSpeechDiagnostics(
  PiperSpeechSynthesizer piper,
  JustAudioGeneratedSpeechPlayer player,
) {
  final playback = player.playbackProbe;
  return 'synthesis_attempts=${piper.synthesisAttempts}, '
      'synthesis_settlements=${piper.synthesisSettlements}, '
      'samples=${piper.lastSampleCount}, '
      'sample_rate=${piper.lastSampleRateHz}, '
      'playback_started=${playback.startedCount}, '
      'playback_completed=${playback.completedCount}, '
      'playback_failed=${playback.failedCount}';
}

Future<DateTime> _waitForPlaybackStart({
  required Future<AppResult<void>> operation,
  required PiperSpeechSynthesizer piper,
  required JustAudioGeneratedSpeechPlayer player,
  required int startedAfter,
  required Duration timeout,
}) async {
  AppResult<void>? settledResult;
  Object? unexpectedError;
  var settled = false;
  unawaited(
    operation.then<void>(
      (result) {
        settledResult = result;
        settled = true;
      },
      onError: (Object error, StackTrace _) {
        unexpectedError = error;
        settled = true;
      },
    ),
  );

  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    final probe = player.playbackProbe;
    if (probe.startedCount > startedAfter && probe.isPlaying) {
      return DateTime.now().toUtc();
    }
    if (settled) {
      final result = settledResult;
      if (result case AppError<void>(:final failure)) {
        fail(
          'Piper speech failed before native playback started: '
          '${_failureDescription(failure)}.',
        );
      }
      fail(
        'Piper speech settled before it could be interrupted during playback: '
        '${unexpectedError ?? 'successful early completion'}; '
        '${_nativeSpeechDiagnostics(piper, player)}.',
      );
    }
    await Future<void>.delayed(_nativeProbePollInterval);
  }
  fail(
    'Timed out waiting for native Piper playback: '
    'started=${player.playbackProbe.startedCount}; '
    'completed=${player.playbackProbe.completedCount}; '
    'failed=${player.playbackProbe.failedCount}.',
  );
}

Future<void> _pumpUntilFound<CandidateType>(
  WidgetTester tester,
  FinderBase<CandidateType> finder,
) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    await tester.pump(_pollInterval);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for active recorded YOLO inference.');
}

Future<void> _removePinnedPiperCache() async {
  final configuration = AssistantBuildConfiguration.fromEnvironment();
  final manifest = configuration.piperManifest;
  final directory = await const ApplicationSupportModelDirectoryProvider().resolve();
  final archive = File(_childPath(directory.path, manifest.archiveFilename));
  final partialArchive = File('${archive.path}.part');
  final bundle = Directory(_childPath(directory.path, manifest.archiveRoot));
  final staging = Directory('${bundle.path}.extracting');

  for (final file in [archive, partialArchive]) {
    if (file.existsSync()) file.deleteSync();
  }
  for (final target in [bundle, staging]) {
    if (target.existsSync()) target.deleteSync(recursive: true);
  }
}

Future<void> _disposeRuntime(
  WidgetTester tester,
  AppRuntime runtime,
) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> attempt(
    Future<void> Function() operation,
    Duration timeout,
  ) async {
    try {
      await operation().timeout(timeout);
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  await attempt(
    () async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    AssistantAcceptanceDurations.widgetDetach,
  );
  await attempt(runtime.close, AssistantAcceptanceDurations.runtimeClose);
  await attempt(
    () => appDependencies.reset(dispose: false),
    AssistantAcceptanceDurations.dependencyReset,
  );

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

void _expectSuccess(AppResult<void> result, {required String stage}) {
  if (result case AppError<void>(:final failure)) {
    fail('Piper $stage failed: ${_failureDescription(failure)}.');
  }
}

String _failureDescription(Object? failure) {
  if (failure is! AppFailure) return 'unknown';
  final message = failure.message;
  return message == null || message.isEmpty ? failure.code : '${failure.code}: $message';
}

String _childPath(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}

final class _OfflineGuardDownloader implements ModelArtifactDownloader {
  final HttpModelArtifactDownloader _delegate = HttpModelArtifactDownloader();

  bool rejectDownloads = false;
  int downloadCalls = 0;
  final List<Uri> sources = <Uri>[];

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) {
    downloadCalls += 1;
    sources.add(source);
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

final class _ScenarioAndCleanupFailure implements Exception {
  const _ScenarioAndCleanupFailure(this.scenarioError, this.cleanupError);

  final Object scenarioError;
  final Object cleanupError;

  @override
  String toString() =>
      'Piper acceptance failed: $scenarioError; '
      'cleanup also failed: $cleanupError';
}
