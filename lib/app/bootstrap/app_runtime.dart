import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// An application resource failed to release its normalized native ownership.
final class AppRuntimeCloseException implements Exception {
  /// Creates a teardown exception retaining the original [failure].
  const AppRuntimeCloseException(this.failure);

  /// The normalized resource failure reported during shutdown.
  final AppFailure failure;

  @override
  String toString() => 'AppRuntimeCloseException(${failure.code})';
}

/// The process-level owner of application resources and their lifecycle.
///
/// Dependency registration constructs this object without side effects. [start]
/// begins observation and scene tracking after model setup, while [close] is
/// the single shutdown boundary. Destination and app-lifecycle reconciliation
/// is serialized: every release request starts observer and camera quiescence
/// together, and the latest acquisition intent runs only after both settle.
/// Shutdown wins an overlap with startup by invalidating the startup wait
/// before either owned resource begins closing.
final class AppRuntime with WidgetsBindingObserver {
  /// Creates the process owner for camera, generation, ASR, and speech ports.
  AppRuntime({
    required this.cameraBloc,
    required this.sceneSession,
    required this.observerBloc,
    required this.modelStore,
    required this.asrModelStore,
    required this.commentGenerator,
    required this.speechRecognizer,
    required this.speechSynthesizer,
    this.modelPackController,
    this.standalonePiperModelStore,
  });

  /// The process-owned camera state machine.
  final CameraBloc cameraBloc;

  /// The process-owned stable-scene publisher.
  final ObservationSceneSession sceneSession;

  /// The process-owned automatic observer and manual assistant state machine.
  final ObserverBloc observerBloc;

  /// The process-owned verified model lifecycle.
  final QwenModelStore modelStore;

  /// The process-owned verified streaming-ASR bundle lifecycle.
  final AsrModelStore asrModelStore;

  /// The process-owned native text-generation runtime.
  final CommentGenerator commentGenerator;

  /// The process-owned microphone capture and native ASR runtime.
  final SpeechRecognizer speechRecognizer;

  /// The process-owned foreground system speech runtime.
  final SpeechSynthesizer speechSynthesizer;

  /// The optional root-gate coordinator detached before its subscribed stores.
  final ModelPackController? modelPackController;

  /// A Piper store not already owned by the configured speech synthesizer.
  final ModelStore<VerifiedPiperModelBundle>? standalonePiperModelStore;

  late final Future<void> _startFuture;
  Future<void>? _rejectedStartFuture;
  Future<void>? _closeFuture;
  Future<void>? _resourceReconciliationTask;
  final Completer<void> _closeRequested = Completer<void>();
  _AppRuntimePhase _phase = _AppRuntimePhase.idle;
  bool _bindingObserverRegistered = false;
  bool _appForegrounded = true;
  bool _assistantDestinationActive = true;
  var _lifecycleEpoch = 0;
  final ValueNotifier<bool> _privacyCoverVisible = ValueNotifier(false);

  static final AppLogger _logger = AppLogger('AppRuntime');

  /// Whether the root must hide all scene-bearing content immediately.
  ValueListenable<bool> get privacyCoverVisible => _privacyCoverVisible;

  /// Starts camera discovery and waits until the initial power state settles.
  ///
  /// Concurrent and subsequent calls while active share the first startup
  /// operation. Starting after shutdown begins fails without reacquiring any
  /// resources.
  Future<void> start() {
    switch (_phase) {
      case _AppRuntimePhase.idle:
        _phase = _AppRuntimePhase.starting;
        return _startFuture = _start();
      case _AppRuntimePhase.starting || _AppRuntimePhase.running:
        return _startFuture;
      case _AppRuntimePhase.closing || _AppRuntimePhase.closed:
        return _rejectedStartFuture ??= Future<void>.error(
          StateError('AppRuntime cannot start after close.'),
        );
    }
  }

  Future<void> _start() async {
    try {
      // Subscribe before observing app lifecycle so a close callback can never
      // target a scene session that startup has not acquired yet.
      sceneSession.start();
      WidgetsBinding.instance.addObserver(this);
      _bindingObserverRegistered = true;

      // Let a same-turn close invalidate startup before CameraStarted enters
      // the Bloc queue; closing a Bloc with that intent still queued would let
      // its handler attempt to schedule reconciliation on a closing Bloc.
      await Future.any<void>([
        Future<void>.value(),
        _closeRequested.future,
      ]);
      if (_closeRequested.isCompleted) return;

      final observerStarted = observerBloc.state.started
          ? null
          : observerBloc.stream.firstWhere((state) => state.started);
      final cameraSettled = _isCameraSettled(cameraBloc.state) ? null : cameraBloc.stream.firstWhere(_isCameraSettled);
      observerBloc.add(const ObserverStarted());
      cameraBloc.add(const CameraStarted());
      await Future.any<void>([
        Future.wait<void>([
          ?cameraSettled?.then<void>((_) {}),
          ?observerStarted?.then<void>((_) {}),
        ]),
        _closeRequested.future,
      ]);
      if (_closeRequested.isCompleted) return;
      _phase = _AppRuntimePhase.running;
      if (!_assistantMayOwnResources) {
        await _enqueueResourceReconciliation(
          () => _quiesceObserverAndDeactivateCamera(
            _lifecycleEpoch,
            suspendModels: !_appForegrounded,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      // A close request invalidates the settlement wait; stream completion from
      // that teardown is cancellation, not a startup failure.
      if (_closeRequested.isCompleted) return;
      try {
        await close();
      } on Object {
        // The original startup error remains the actionable failure. The shared
        // close future still preserves the teardown error for close callers.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Reconciles foreground resources with the selected root destination.
  ///
  /// Destination changes use serialized latest-wins semantics. Entering
  /// Settings rejects new observer work while camera teardown begins in
  /// parallel. Returning to Assistant reacquires only after both release paths
  /// settle and only when the app is active; explicit camera/observer pause
  /// intent remains authoritative in each Bloc.
  Future<void> setAssistantDestinationActive({required bool active}) {
    if (_phase == _AppRuntimePhase.closing || _phase == _AppRuntimePhase.closed) {
      return Future.value();
    }
    if (_assistantDestinationActive == active) {
      return _resourceReconciliationTask ?? Future.value();
    }
    _assistantDestinationActive = active;
    final epoch = ++_lifecycleEpoch;
    if (_phase == _AppRuntimePhase.idle) return Future.value();
    if (!active) {
      return _enqueueResourceReconciliation(
        () => _quiesceObserverAndDeactivateCamera(
          epoch,
          suspendModels: !_appForegrounded,
        ),
      );
    }
    return _enqueueResourceReconciliation(
      () => _resumeAssistantIfAllowed(epoch),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_appForegrounded) return;
        _appForegrounded = true;
        final epoch = ++_lifecycleEpoch;
        unawaited(
          _enqueueResourceReconciliation(
            () => _resumeAssistantIfAllowed(epoch),
          ),
        );
      case AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.paused:
        if (!_appForegrounded) return;
        _appForegrounded = false;
        _privacyCoverVisible.value = true;
        final epoch = ++_lifecycleEpoch;
        unawaited(
          _enqueueResourceReconciliation(
            () => _quiesceObserverAndDeactivateCamera(
              epoch,
              suspendModels: true,
            ),
          ),
        );
      case AppLifecycleState.detached:
        _appForegrounded = false;
        _privacyCoverVisible.value = true;
        _lifecycleEpoch += 1;
        unawaited(close());
    }
  }

  Future<void> _enqueueResourceReconciliation(
    Future<void> Function() reconcile,
  ) {
    final predecessor = _resourceReconciliationTask;
    late final Future<void> task;
    task = (() async {
      if (predecessor != null) {
        try {
          await predecessor;
        } on Object {
          // The latest lifecycle intent must still run after an earlier
          // reconciliation reports its already-logged resource failure.
        }
      }
      await reconcile();
    })();
    _resourceReconciliationTask = task;
    unawaited(
      task.then<void>(
        (_) => _clearResourceReconciliationTask(task),
        onError: (Object _, StackTrace _) {
          _clearResourceReconciliationTask(task);
        },
      ),
    );
    return task;
  }

  void _clearResourceReconciliationTask(Future<void> task) {
    if (identical(_resourceReconciliationTask, task)) {
      _resourceReconciliationTask = null;
    }
  }

  Future<void> _quiesceObserverAndDeactivateCamera(
    int epoch, {
    required bool suspendModels,
  }) async {
    try {
      Future<void>? observerQuiesced;
      if (!observerBloc.isClosed && observerBloc.state.started && observerBloc.state.foregroundActive) {
        observerQuiesced = observerBloc.stream.firstWhere(
          (state) => !state.foregroundActive && !state.isGenerating && !state.isSpeaking,
        );
        observerBloc.add(const ObserverForegroundDeactivated());
      }

      Future<void>? cameraSettled;
      if (!cameraBloc.isClosed) {
        cameraSettled = _isCameraInactive(cameraBloc.state) ? null : cameraBloc.stream.firstWhere(_isCameraInactive);
        cameraBloc.add(
          const CameraSurfaceActivityChanged(active: false),
        );
      }

      // A later resume changes the epoch but does not cancel this release.
      // Waiting for both owners preserves the serialized disable-then-enable
      // boundary while camera privacy no longer depends on slow native speech,
      // generation, or microphone cancellation.
      await Future.wait<void>([
        ?observerQuiesced,
        ?cameraSettled,
      ]);

      if (epoch != _lifecycleEpoch ||
          _assistantMayOwnResources ||
          !suspendModels ||
          _phase == _AppRuntimePhase.closing ||
          _phase == _AppRuntimePhase.closed ||
          observerBloc.isClosed) {
        return;
      }
      // Both runtimes can submit native accelerator work. Ticks and generation
      // are already quiescent; let the camera controller settle before freeing
      // llama.cpp so teardown cannot race its final inference submission.
      observerBloc.add(const ObserverSuspended());
    } on Object catch (error, stackTrace) {
      if (_phase == _AppRuntimePhase.closing || _phase == _AppRuntimePhase.closed) {
        return;
      }
      _logger.e(
        'Failed to quiesce observer and camera resources.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _resumeAssistantIfAllowed(int epoch) async {
    if (_phase == _AppRuntimePhase.closing || _phase == _AppRuntimePhase.closed) {
      return;
    }
    if (epoch != _lifecycleEpoch || !_assistantMayOwnResources) {
      if (epoch == _lifecycleEpoch && _appForegrounded && !_assistantDestinationActive) {
        _privacyCoverVisible.value = false;
      }
      return;
    }
    try {
      if (!observerBloc.isClosed && observerBloc.state.started) {
        // Queue resume even while deactivation still reports foreground=true.
        // Observer events are sequential, so this latest intent runs after the
        // in-flight quiescence instead of being lost in a rapid return.
        observerBloc.add(const ObserverResumed());
      }
      if (!cameraBloc.isClosed) {
        final cameraSettled = _isCameraSettledForActiveSurface(cameraBloc.state)
            ? null
            : cameraBloc.stream.firstWhere(_isCameraSettledForActiveSurface);
        cameraBloc.add(const CameraSurfaceActivityChanged(active: true));
        await cameraSettled;
      }
      if (epoch == _lifecycleEpoch && _assistantMayOwnResources) {
        _privacyCoverVisible.value = false;
      }
    } on Object catch (error, stackTrace) {
      if (epoch != _lifecycleEpoch || _phase == _AppRuntimePhase.closing || _phase == _AppRuntimePhase.closed) {
        return;
      }
      _logger.e(
        'Failed to reacquire assistant resources.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool get _assistantMayOwnResources {
    return _appForegrounded && _assistantDestinationActive;
  }

  /// Releases process-owned resources exactly once.
  ///
  /// Concurrent calls share one attempt. A successful attempt stays
  /// idempotent; a failed attempt may be retried while every owner is retained.
  Future<void> close() {
    final existingTask = _closeFuture;
    if (existingTask != null) return existingTask;

    final completion = Completer<void>();
    _closeFuture = completion.future;
    _phase = _AppRuntimePhase.closing;
    _privacyCoverVisible.value = true;
    _lifecycleEpoch += 1;
    if (!_closeRequested.isCompleted) _closeRequested.complete();
    final closeFuture = completion.future;
    unawaited(
      _close().then<void>(
        completion.complete,
        onError: (Object error, StackTrace stackTrace) {
          // Every owner remains referenced after a failed teardown. Clear only
          // the failed attempt so a later close can retry retained native state.
          if (identical(_closeFuture, closeFuture)) _closeFuture = null;
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return closeFuture;
  }

  Future<void> _close() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> closeOwner(Future<void> Function() close) async {
      try {
        await close();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    try {
      try {
        if (_bindingObserverRegistered) {
          WidgetsBinding.instance.removeObserver(this);
        }
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        _bindingObserverRegistered = false;
        // The setup gate subscribes directly to model stores. Detach it before
        // any consumer or store can close its state stream.
        final modelPack = modelPackController;
        if (modelPack != null) await closeOwner(modelPack.close);
        // Stop the timer and generation owner before camera shutdown so it can
        // no longer submit work from a late tick. Camera-side owners may then
        // close concurrently before app-owned model ports are destroyed.
        await closeOwner(observerBloc.close);
        await Future.wait<void>([
          closeOwner(sceneSession.close),
          closeOwner(cameraBloc.close),
        ]);
        await Future.wait<void>([
          closeOwner(_closeModelResources),
          closeOwner(_closeVoiceInputResources),
          closeOwner(_closeSpeechResource),
        ]);
      }

      if (firstError case final error?) {
        Error.throwWithStackTrace(error, firstStackTrace!);
      }
    } finally {
      _phase = _AppRuntimePhase.closed;
    }
  }

  Future<void> _closeModelResources() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> closeResource(Future<void> Function() close) async {
      try {
        await close();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    // The already-quiescent Bloc no longer consumes these ports. Stop artifact
    // acquisition before the generator destroys its independently owned native
    // runtime.
    await closeResource(modelStore.close);
    final standalonePiper = standalonePiperModelStore;
    if (standalonePiper != null) {
      await closeResource(standalonePiper.close);
    }
    await closeResource(commentGenerator.close);

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> _closeSpeechResource() async {
    final result = await speechSynthesizer.close();
    if (result case AppError<void>(:final failure)) {
      throw AppRuntimeCloseException(failure);
    }
  }

  Future<void> _closeVoiceInputResources() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> closeResource(Future<void> Function() close) async {
      try {
        await close();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    // The Bloc has stopped capture and detached its model-state subscription.
    // Close preparation before native recognition so a late verified bundle
    // can no longer be handed to a recognizer that is being destroyed.
    await closeResource(asrModelStore.close);
    await closeResource(_closeSpeechRecognizerResource);

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> _closeSpeechRecognizerResource() async {
    final result = await speechRecognizer.close();
    if (result case AppError<void>(:final failure)) {
      throw AppRuntimeCloseException(failure);
    }
  }
}

enum _AppRuntimePhase { idle, starting, running, closing, closed }

bool _isCameraSettled(CameraState state) {
  if (state.status == CameraStatus.failure) return true;
  final shouldEnable = state.requestedEnabled && state.surfaceActive && state.availableLenses.isNotEmpty;
  return shouldEnable ? state.status == CameraStatus.enabled : state.status == CameraStatus.disabled;
}

bool _isCameraInactive(CameraState state) {
  return state.status == CameraStatus.disabled || state.status == CameraStatus.failure;
}

bool _isCameraSettledForActiveSurface(CameraState state) {
  if (!state.surfaceActive) return false;
  if (state.status == CameraStatus.failure) return true;
  return state.requestedEnabled && state.availableLenses.isNotEmpty
      ? state.status == CameraStatus.enabled
      : state.status == CameraStatus.disabled;
}
