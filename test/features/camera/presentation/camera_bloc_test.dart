import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_state.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

import '../../../support/fake_camera_controller.dart';

void main() {
  test('initializes rear camera through the expected state sequence', () async {
    final controller = FakeCameraController();
    final bloc = CameraBloc(controller);
    final statuses = <CameraStatus>[];
    final subscription = bloc.stream.listen(
      (state) => statuses.add(state.status),
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
