import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

const testObservationSurfaceKey = Key('test-observation-surface');

Widget buildTestObservationSurface(BuildContext _) {
  return const ColoredBox(
    key: testObservationSurfaceKey,
    color: CupertinoColors.black,
    child: Center(
      child: Text(
        'Test observation surface',
        style: TextStyle(color: CupertinoColors.white),
      ),
    ),
  );
}

final class FakeCameraController implements ObservationController {
  FakeCameraController({
    CameraCapabilities? capabilities,
    bool broadcastEvents = true,
    this.initFailure,
    this.enableFailure,
    this.disableFailure,
    this.retryModelFailure,
    this.retryObservationFailure,
    this.openPermissionSettingsFailure,
    this.emitModelReadyOnInit = true,
    this.onInit,
    this.onEnable,
    this.onDisable,
    this.onRetryModel,
    this.onRetryObservation,
    this.onOpenPermissionSettings,
    this.onClose,
  }) : _events = broadcastEvents
           ? StreamController<ObservationEvent>.broadcast(sync: true)
           : StreamController<ObservationEvent>(sync: true),
       capabilities =
           capabilities ??
           CameraCapabilities(
             availableLenses: const [CameraLens.back, CameraLens.front],
             preferredLens: CameraLens.back,
           );

  final StreamController<ObservationEvent> _events;

  CameraCapabilities capabilities;
  AppFailure? initFailure;
  AppFailure? enableFailure;
  AppFailure? disableFailure;
  AppFailure? retryModelFailure;
  AppFailure? retryObservationFailure;
  AppFailure? openPermissionSettingsFailure;
  bool emitModelReadyOnInit;
  Future<void> Function()? onInit;
  Future<void> Function(CameraLens lens)? onEnable;
  Future<void> Function()? onDisable;
  Future<void> Function()? onRetryModel;
  Future<void> Function()? onRetryObservation;
  Future<void> Function()? onOpenPermissionSettings;
  Future<void> Function()? onClose;

  int initCalls = 0;
  int disableCalls = 0;
  int retryModelCalls = 0;
  int retryObservationCalls = 0;
  int openPermissionSettingsCalls = 0;
  int closeCalls = 0;
  final List<CameraLens> enableCalls = [];

  @override
  Stream<ObservationEvent> get events => _events.stream;

  void emit(ObservationEvent event) => _events.add(event);

  @override
  Future<AppResult<CameraCapabilities>> init() async {
    initCalls += 1;
    await onInit?.call();
    if (emitModelReadyOnInit) {
      emit(const ObservationModelReady());
    }
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
    await onDisable?.call();
    final failure = disableFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  @override
  Future<AppResult<void>> retryModel() async {
    retryModelCalls += 1;
    await onRetryModel?.call();
    final failure = retryModelFailure;
    if (failure != null) return AppError<void>(failure);
    emit(const ObservationModelReady());
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryObservation() async {
    retryObservationCalls += 1;
    await onRetryObservation?.call();
    final failure = retryObservationFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  @override
  Future<AppResult<void>> openPermissionSettings() async {
    openPermissionSettingsCalls += 1;
    await onOpenPermissionSettings?.call();
    final failure = openPermissionSettingsFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await onClose?.call();
    if (!_events.isClosed) await _events.close();
  }
}
