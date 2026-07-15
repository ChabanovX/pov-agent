import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_cubit.dart';

/// Owns process-level application resources and their lifecycle.
///
/// Dependency registration constructs this object without side effects. [start]
/// begins the camera session, while [close] is the single shutdown boundary.
final class AppRuntime with WidgetsBindingObserver {
  AppRuntime({
    required this.cameraCubit,
    required this.cameraPreview,
  });

  final CameraCubit cameraCubit;
  final Widget cameraPreview;

  Future<void>? _startFuture;
  Future<void>? _closeFuture;

  Future<void> start() {
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    WidgetsBinding.instance.addObserver(this);
    await cameraCubit.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    unawaited(_closeAfterSurfaceDeactivation());
  }

  Future<void> _closeAfterSurfaceDeactivation() async {
    await cameraCubit.setSurfaceActive(active: false);
    await close();
  }

  Future<void> close() {
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    WidgetsBinding.instance.removeObserver(this);
    await cameraCubit.close();
  }
}
