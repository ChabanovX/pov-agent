import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/camera_controller.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_frame.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

const testCameraPreviewKey = Key('test-camera-preview');

Widget buildTestCameraPreview(BuildContext _) {
  return const ColoredBox(
    key: testCameraPreviewKey,
    color: CupertinoColors.black,
    child: Center(
      child: Text(
        'Test camera preview',
        style: TextStyle(color: CupertinoColors.white),
      ),
    ),
  );
}

final class FakeCameraController implements CameraController {
  FakeCameraController({
    CameraCapabilities? capabilities,
    this.initFailure,
    this.enableFailure,
    this.disableFailure,
    this.onEnable,
  }) : capabilities =
           capabilities ??
           CameraCapabilities(
             availableLenses: const [CameraLens.back, CameraLens.front],
             preferredLens: CameraLens.back,
           );

  final StreamController<AppResult<CameraFrame>> _frames = StreamController<AppResult<CameraFrame>>.broadcast();

  CameraCapabilities capabilities;
  AppFailure? initFailure;
  AppFailure? enableFailure;
  AppFailure? disableFailure;
  Future<void> Function(CameraLens lens)? onEnable;

  int initCalls = 0;
  int disableCalls = 0;
  int closeCalls = 0;
  final List<CameraLens> enableCalls = [];

  @override
  Stream<AppResult<CameraFrame>> get frames => _frames.stream;

  @override
  Future<AppResult<CameraCapabilities>> init() async {
    initCalls += 1;
    final failure = initFailure;
    return failure == null ? AppSuccess(capabilities) : AppError(failure);
  }

  @override
  Future<AppResult<void>> enable(CameraLens lens) async {
    enableCalls.add(lens);
    await onEnable?.call(lens);
    final failure = enableFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  @override
  Future<AppResult<void>> disable() async {
    disableCalls += 1;
    final failure = disableFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (!_frames.isClosed) await _frames.close();
  }
}
