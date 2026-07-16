import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_state.dart';

/// Owns process-level application resources and their lifecycle.
///
/// Dependency registration constructs this object without side effects. [start]
/// begins the camera session, while [close] is the single shutdown boundary.
final class AppRuntime with WidgetsBindingObserver {
  AppRuntime({
    required this.cameraBloc,
    required this.cameraPreview,
  });

  final CameraBloc cameraBloc;
  final Widget cameraPreview;

  Future<void>? _startFuture;
  Future<void>? _closeFuture;

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
