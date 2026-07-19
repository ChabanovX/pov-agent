import 'dart:async';

import 'package:flutter/widgets.dart';
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
  });

  /// The process-owned camera state machine.
  final CameraBloc cameraBloc;

  /// The process-owned stable-scene publisher.
  final ObservationSceneSession sceneSession;

  late final Future<void> _startFuture;
  Future<void>? _rejectedStartFuture;
  Future<void>? _closeFuture;
  final Completer<void> _closeRequested = Completer<void>();
  _AppRuntimePhase _phase = _AppRuntimePhase.idle;
  bool _bindingObserverRegistered = false;

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
    if (state != AppLifecycleState.detached) return;
    unawaited(close());
  }

  /// Releases process-owned resources exactly once.
  ///
  /// Concurrent and subsequent calls share the first shutdown operation.
  Future<void> close() {
    final existingTask = _closeFuture;
    if (existingTask != null) return existingTask;

    final completion = Completer<void>();
    _closeFuture = completion.future;
    _phase = _AppRuntimePhase.closing;
    _closeRequested.complete();
    unawaited(
      _close().then<void>(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<void> _close() async {
    try {
      try {
        if (_bindingObserverRegistered) {
          WidgetsBinding.instance.removeObserver(this);
        }
      } finally {
        _bindingObserverRegistered = false;
        // These owners can shut down independently. Start both tasks before
        // awaiting so an asynchronous failure in one cannot skip the other.
        await Future.wait<void>([
          sceneSession.close(),
          cameraBloc.close(),
        ]);
      }
    } finally {
      _phase = _AppRuntimePhase.closed;
    }
  }
}

enum _AppRuntimePhase { idle, starting, running, closing, closed }

bool _isCameraSettled(CameraState state) {
  if (state.status == CameraStatus.failure) return true;
  final shouldEnable = state.requestedEnabled && state.surfaceActive;
  return shouldEnable ? state.status == CameraStatus.enabled : state.status == CameraStatus.disabled;
}
