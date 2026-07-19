import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_state.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

import '../../../support/fake_camera_controller.dart';

void main() {
  test('initializes rear camera through the expected state sequence', () async {
    final controller = FakeCameraController();
    final bloc = CameraBloc(controller);
    final statuses = <CameraStatus>[];
    final subscription = bloc.stream.listen(
      (state) {
        if (statuses.lastOrNull != state.status) {
          statuses.add(state.status);
        }
      },
    );

    bloc.add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    expect(
      statuses,
      [
        CameraStatus.initializing,
        CameraStatus.disabled,
        CameraStatus.initializing,
        CameraStatus.enabled,
      ],
    );
    expect(bloc.state.selectedLens, CameraLens.back);
    expect(bloc.state.modelStatus, ObservationModelStatus.ready);
    expect(bloc.state.surfaceMounted, isTrue);
    expect(controller.enableCalls, [CameraLens.back]);

    await subscription.cancel();
    await bloc.close();
  });

  test('switches to the latest requested lens serially', () async {
    final firstEnableStarted = Completer<void>();
    final firstEnableGate = Completer<void>();
    var enableCount = 0;
    final controller = FakeCameraController(
      onEnable: (_) async {
        enableCount += 1;
        if (enableCount != 1) return;
        firstEnableStarted.complete();
        await firstEnableGate.future;
      },
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await firstEnableStarted.future;
    bloc.add(const CameraLensToggleRequested());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.switching && state.selectedLens == CameraLens.front,
    );
    expect(controller.enableCalls, [CameraLens.back]);

    firstEnableGate.complete();
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled && state.selectedLens == CameraLens.front,
    );

    expect(controller.enableCalls, [CameraLens.back, CameraLens.front]);

    await bloc.close();
  });

  test('inactive intent during discovery prevents native enable', () async {
    final initStarted = Completer<void>();
    final initGate = Completer<void>();
    final controller = FakeCameraController(
      onInit: () async {
        initStarted.complete();
        await initGate.future;
      },
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await initStarted.future;
    bloc.add(const CameraSurfaceActivityChanged(active: false));
    await _waitForState(bloc, (state) => !state.surfaceActive);

    initGate.complete();
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.disabled,
    );

    expect(controller.enableCalls, isEmpty);
    expect(bloc.state.requestedEnabled, isTrue);

    await bloc.close();
  });

  test('suspends automatically but preserves manual power preference', () async {
    final controller = FakeCameraController();
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    bloc.add(const CameraSurfaceActivityChanged(active: false));
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.disabled,
    );
    expect(controller.disableCalls, 1);
    expect(bloc.state.requestedEnabled, isTrue);

    bloc.add(const CameraSurfaceActivityChanged(active: true));
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );
    expect(controller.enableCalls, [CameraLens.back, CameraLens.back]);

    bloc.add(const CameraDisableRequested());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.disabled && !state.requestedEnabled,
    );
    bloc
      ..add(const CameraSurfaceActivityChanged(active: false))
      ..add(const CameraSurfaceActivityChanged(active: true));
    await pumpEventQueue();

    expect(bloc.state.requestedEnabled, isFalse);
    expect(bloc.state.status, CameraStatus.disabled);
    expect(controller.enableCalls, [CameraLens.back, CameraLens.back]);

    await bloc.close();
  });

  test('preserves permission failure across visibility changes and retries', () async {
    final controller = FakeCameraController(
      initFailure: const PermissionDeniedFailure(),
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.failure,
    );

    bloc
      ..add(const CameraSurfaceActivityChanged(active: false))
      ..add(const CameraSurfaceActivityChanged(active: true));
    await pumpEventQueue();

    expect(bloc.state.status, CameraStatus.failure);
    expect(bloc.state.failure, isA<PermissionDeniedFailure>());
    expect(controller.initCalls, 1);
    expect(controller.enableCalls, isEmpty);

    controller.initFailure = null;
    bloc.add(const CameraRetryRequested());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    expect(controller.initCalls, 2);

    await bloc.close();
  });

  test('tracks download, detections, diagnostics, and model retry', () async {
    final controller = FakeCameraController(emitModelReadyOnInit: false);
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    controller
      ..emit(const ObservationModelDownloadProgressed(0.42))
      ..emit(
        ObservationDetectionsUpdated(
          detections: const [
            Detection(
              classId: 0,
              label: 'person',
              confidence: 0.9,
              box: NormalizedBox(
                left: 0.1,
                top: 0.1,
                right: 0.5,
                bottom: 0.9,
              ),
            ),
          ],
          observedAt: DateTime.utc(2026, 7, 16),
        ),
      )
      ..emit(
        ObservationDiagnosticsUpdated(
          ObservationDiagnostics(
            framesPerSecond: 18,
            inferenceTimeMs: 24,
            processingTimeMs: 30,
            frameNumber: 12,
            sampledAt: DateTime.utc(2026, 7, 16),
          ),
        ),
      );
    await _waitForState(
      bloc,
      (state) => state.diagnostics?.frameNumber == 12,
    );

    expect(bloc.state.modelStatus, ObservationModelStatus.downloading);
    expect(bloc.state.modelDownloadProgress, 0.42);
    expect(bloc.state.detections.single.label, 'person');

    controller.emit(
      const ObservationFailed(NetworkFailure(code: 'model_download')),
    );
    await _waitForState(
      bloc,
      (state) => state.modelStatus == ObservationModelStatus.failure,
    );
    expect(bloc.state.detections, isEmpty);
    expect(bloc.state.diagnostics, isNull);

    bloc.add(const CameraRetryRequested());
    await _waitForState(
      bloc,
      (state) => state.modelStatus == ObservationModelStatus.ready,
    );

    expect(controller.retryModelCalls, 1);
    expect(controller.initCalls, 1);

    await bloc.close();
  });

  test('separates inference failure and retries observation only', () async {
    final controller = FakeCameraController();
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed'),
      ),
    );
    await _waitForState(
      bloc,
      (state) => state.observationFailure != null,
    );

    expect(bloc.state.modelStatus, ObservationModelStatus.ready);
    expect(bloc.state.modelFailure, isNull);
    expect(bloc.state.detections, isEmpty);
    expect(bloc.state.diagnostics, isNull);

    bloc.add(const CameraRetryRequested());
    await _waitForState(
      bloc,
      (state) => state.observationFailure == null,
    );
    await pumpEventQueue();

    expect(controller.retryObservationCalls, 1);
    expect(controller.retryModelCalls, 0);
    expect(controller.initCalls, 1);

    await bloc.close();
  });

  test('coalesces repeated inference retries until a new result', () async {
    final retryStarted = Completer<void>();
    final retryGate = Completer<void>();
    var retryNumber = 0;
    final controller = FakeCameraController(
      onRetryObservation: () async {
        retryNumber += 1;
        if (retryNumber == 1) {
          retryStarted.complete();
          await retryGate.future;
        }
      },
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );
    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed'),
      ),
    );
    await _waitForState(
      bloc,
      (state) => state.observationFailure != null,
    );

    bloc
      ..add(const CameraRetryRequested())
      ..add(const CameraRetryRequested());
    await retryStarted.future;
    await pumpEventQueue();

    expect(controller.retryObservationCalls, 1);
    expect(controller.retryModelCalls, 0);
    expect(controller.initCalls, 1);

    retryGate.complete();
    await pumpEventQueue();
    expect(controller.retryObservationCalls, 1);
    expect(controller.retryModelCalls, 0);
    expect(controller.initCalls, 1);

    final resultApplied = bloc.stream.first;
    controller.emit(
      ObservationDetectionsUpdated(
        detections: const [],
        observedAt: DateTime.utc(2026, 7, 17),
      ),
    );
    await resultApplied;

    // With no failure left, this intent must follow the generic retry path.
    // If the empty result did not release observation coalescing, it would be
    // incorrectly swallowed as another observation retry.
    bloc.add(const CameraRetryRequested());
    await pumpEventQueue();
    expect(controller.retryObservationCalls, 1);
    expect(controller.retryModelCalls, 1);
    expect(controller.initCalls, 2);

    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed_again'),
      ),
    );
    await _waitForState(
      bloc,
      (state) => state.observationFailure?.code == 'inference_failed_again',
    );

    bloc.add(const CameraRetryRequested());
    await pumpEventQueue();
    expect(controller.retryObservationCalls, 2);
    expect(controller.retryModelCalls, 1);
    expect(controller.initCalls, 2);

    await bloc.close();
  });

  test('keeps an exact observation failure when retry fails', () async {
    const retryFailure = DeviceUnavailableFailure(
      code: 'observation_retry_failed',
    );
    final controller = FakeCameraController(
      retryObservationFailure: retryFailure,
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );
    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed'),
      ),
    );
    await _waitForState(
      bloc,
      (state) => state.observationFailure != null,
    );

    bloc.add(const CameraRetryRequested());
    await _waitForState(
      bloc,
      (state) => state.observationFailure?.code == retryFailure.code,
    );

    expect(bloc.state.observationFailure, same(retryFailure));
    expect(bloc.state.modelStatus, ObservationModelStatus.ready);
    expect(controller.retryObservationCalls, 1);
    expect(controller.retryModelCalls, 0);

    await bloc.close();
  });

  test('close seals event admission before controller teardown', () async {
    final closeStarted = Completer<void>();
    final closeGate = Completer<void>();
    final controller = FakeCameraController(
      onClose: () async {
        closeStarted.complete();
        await closeGate.future;
      },
    );
    final bloc = CameraBloc(controller)..add(const CameraStarted());
    await _waitForState(
      bloc,
      (state) => state.status == CameraStatus.enabled,
    );

    final closeFuture = bloc.close();
    expect(
      () => bloc.add(const CameraLensToggleRequested()),
      throwsA(isA<StateError>()),
    );

    await closeStarted.future;
    closeGate.complete();
    await closeFuture;
    expect(controller.closeCalls, 1);
  });
}

Future<CameraState> _waitForState(
  CameraBloc bloc,
  bool Function(CameraState state) predicate,
) {
  if (predicate(bloc.state)) return Future.value(bloc.state);
  return bloc.stream.firstWhere(predicate);
}
