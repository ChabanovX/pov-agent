import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';

/// The process-level owner of application resources and their lifecycle.
///
/// Dependency registration constructs this object without side effects. [start]
/// begins the camera session, while [close] is the single shutdown boundary.
final class AppRuntime with WidgetsBindingObserver {
  /// Creates a runtime for [cameraBloc].
  AppRuntime({
    required this.cameraBloc,
  });

  /// The process-owned camera state machine.
  final CameraBloc cameraBloc;

  Future<void>? _startFuture;
  Future<void>? _closeFuture;

  /// Starts camera discovery and waits until the initial power state settles.
  ///
  /// Concurrent and subsequent calls share the first startup operation.
  Future<void> start() {
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    WidgetsBinding.instance.addObserver(this);
    final settled = cameraBloc.stream.firstWhere(_isCameraSettled);
    cameraBloc.add(const CameraStarted());
    await settled;
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
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    WidgetsBinding.instance.removeObserver(this);
    await cameraBloc.close();
  }
}

bool _isCameraSettled(CameraState state) {
  if (state.status == CameraStatus.failure) return true;
  final shouldEnable = state.requestedEnabled && state.surfaceActive;
  return shouldEnable ? state.status == CameraStatus.enabled : state.status == CameraStatus.disabled;
}
