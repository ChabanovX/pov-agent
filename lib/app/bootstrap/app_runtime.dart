import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pov_agent/core/logging/app_logger.dart';
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
/// begins observation and scene tracking, while [close] is the single shutdown
/// boundary. Shutdown wins an overlap with startup: it invalidates the startup
/// wait before either owned resource begins closing.
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

  late final Future<void> _startFuture;
  Future<void>? _rejectedStartFuture;
  Future<void>? _closeFuture;
  final Completer<void> _closeRequested = Completer<void>();
  _AppRuntimePhase _phase = _AppRuntimePhase.idle;
  bool _bindingObserverRegistered = false;
  bool _appForegrounded = true;
  var _lifecycleEpoch = 0;

  static final AppLogger _logger = AppLogger('AppRuntime');

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
      final cameraSettled = cameraBloc.stream.firstWhere(_isCameraSettled);
      observerBloc.add(const ObserverStarted());
      cameraBloc.add(const CameraStarted());
      await Future.any<void>([
        Future.wait<void>([
          cameraSettled.then<void>((_) {}),
          ?observerStarted?.then<void>((_) {}),
        ]),
        _closeRequested.future,
      ]);
      if (_closeRequested.isCompleted) return;
      _phase = _AppRuntimePhase.running;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_appForegrounded) return;
        _appForegrounded = true;
        _lifecycleEpoch += 1;
        if (!observerBloc.isClosed) {
          observerBloc.add(const ObserverResumed());
        }
        if (!cameraBloc.isClosed) {
          cameraBloc.add(
            const CameraSurfaceActivityChanged(active: true),
          );
        }
      case AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.paused:
        if (!_appForegrounded) return;
        _appForegrounded = false;
        final epoch = ++_lifecycleEpoch;
        unawaited(_quiesceObserverThenSuspendAfterCamera(epoch));
      case AppLifecycleState.detached:
        _appForegrounded = false;
        _lifecycleEpoch += 1;
        unawaited(close());
    }
  }

  Future<void> _quiesceObserverThenSuspendAfterCamera(int epoch) async {
    try {
      if (!observerBloc.isClosed && observerBloc.state.foregroundActive) {
        final observerQuiesced = observerBloc.stream.firstWhere(
          (state) => !state.foregroundActive && !state.isGenerating && !state.isSpeaking,
        );
        observerBloc.add(const ObserverForegroundDeactivated());
        await observerQuiesced;
      }

      if (epoch != _lifecycleEpoch || _appForegrounded) return;
      if (!cameraBloc.isClosed) {
        final cameraSettled = _isCameraInactive(cameraBloc.state)
            ? null
            : cameraBloc.stream.firstWhere(_isCameraInactive);
        cameraBloc.add(
          const CameraSurfaceActivityChanged(active: false),
        );
        await cameraSettled;
      }

      if (epoch != _lifecycleEpoch ||
          _appForegrounded ||
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
        'Failed to quiesce observer and camera resources before suspension.',
        error: error,
        stackTrace: stackTrace,
      );
    }
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

    // The already-quiescent Bloc no longer consumes these ports. The store
    // stops preparation and unloads before the generator destroys native state.
    await closeResource(modelStore.close);
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
  final shouldEnable = state.requestedEnabled && state.surfaceActive;
  return shouldEnable ? state.status == CameraStatus.enabled : state.status == CameraStatus.disabled;
}

bool _isCameraInactive(CameraState state) {
  return state.status == CameraStatus.disabled || state.status == CameraStatus.failure;
}
