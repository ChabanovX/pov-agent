import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pov_agent/core/logging/app_logger.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';

/// The process-level owner of application resources and their lifecycle.
///
/// Dependency registration constructs this object without side effects. [start]
/// begins observation and scene tracking, while [close] is the single shutdown
/// boundary. Shutdown wins an overlap with startup: it invalidates the startup
/// wait before either owned resource begins closing.
final class AppRuntime with WidgetsBindingObserver {
  /// Creates a runtime for [cameraBloc] and [sceneSession].
  AppRuntime({
    required this.cameraBloc,
    required this.sceneSession,
    required this.assistantBloc,
    required this.modelStore,
    required this.commentGenerator,
  });

  /// The process-owned camera state machine.
  final CameraBloc cameraBloc;

  /// The process-owned stable-scene publisher.
  final ObservationSceneSession sceneSession;

  /// The process-owned manual assistant state machine.
  final AssistantBloc assistantBloc;

  /// The process-owned verified model lifecycle.
  final ModelStore modelStore;

  /// The process-owned native text-generation runtime.
  final CommentGenerator commentGenerator;

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

      final settled = cameraBloc.stream.firstWhere(_isCameraSettled);
      cameraBloc.add(const CameraStarted());
      await Future.any<void>([
        settled.then<void>((_) {}),
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
        if (!assistantBloc.isClosed) {
          assistantBloc.add(const AssistantResumed());
        }
      case AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.paused:
        if (!_appForegrounded) return;
        _appForegrounded = false;
        final epoch = ++_lifecycleEpoch;
        unawaited(_suspendAssistantAfterCamera(epoch));
      case AppLifecycleState.detached:
        _appForegrounded = false;
        _lifecycleEpoch += 1;
        unawaited(close());
    }
  }

  Future<void> _suspendAssistantAfterCamera(int epoch) async {
    try {
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
          assistantBloc.isClosed) {
        return;
      }
      // Both runtimes can submit Metal work. Let the camera controller settle
      // before freeing llama.cpp so background teardown never races a final
      // camera inference command buffer.
      assistantBloc.add(const AssistantSuspended());
    } on Object catch (error, stackTrace) {
      if (_phase == _AppRuntimePhase.closing || _phase == _AppRuntimePhase.closed) {
        return;
      }
      _logger.e(
        'Failed to settle camera resources before assistant suspension.',
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
        // Stop both camera-side owners before llama.cpp teardown. They may close
        // concurrently with each other, but assistant resources start only once
        // neither owner can submit or observe another camera inference result.
        await Future.wait<void>([
          closeOwner(sceneSession.close),
          closeOwner(cameraBloc.close),
        ]);
        await closeOwner(_closeAssistantResources);
      }

      if (firstError case final error?) {
        Error.throwWithStackTrace(error, firstStackTrace!);
      }
    } finally {
      _phase = _AppRuntimePhase.closed;
    }
  }

  Future<void> _closeAssistantResources() async {
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

    // The Bloc stops consuming first, then the store stops preparation and
    // unloads, and finally the generator destroys its isolate/native handles.
    await closeResource(assistantBloc.close);
    await closeResource(modelStore.close);
    await closeResource(commentGenerator.close);

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
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
