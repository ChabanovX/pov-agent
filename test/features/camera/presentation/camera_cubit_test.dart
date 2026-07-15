import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_cubit.dart';
import 'package:some_camera_with_llm/features/camera/presentation/cubit/camera_state.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';

import '../../../support/fake_camera_controller.dart';

void main() {
  test('initializes rear camera through the expected state sequence', () async {
    final controller = FakeCameraController();
    final cubit = CameraCubit(controller);
    final statuses = <CameraStatus>[];
    final subscription = cubit.stream.listen(
      (state) => statuses.add(state.status),
    );

    await cubit.init();
    await Future<void>.delayed(Duration.zero);

    expect(
      statuses,
      [
        CameraStatus.initializing,
        CameraStatus.disabled,
        CameraStatus.initializing,
        CameraStatus.enabled,
      ],
    );
    expect(cubit.state.selectedLens, CameraLens.back);
    expect(controller.enableCalls, [CameraLens.back]);

    await subscription.cancel();
    await cubit.close();
  });

  test('switches between rear and front lenses serially', () async {
    final firstEnableGate = Completer<void>();
    var enableCount = 0;
    final controller = FakeCameraController(
      onEnable: (_) async {
        enableCount += 1;
        if (enableCount == 1) await firstEnableGate.future;
      },
    );
    final cubit = CameraCubit(controller);

    final initialize = cubit.init();
    final switchLens = cubit.toggleCamera();
    firstEnableGate.complete();
    await Future.wait([initialize, switchLens]);

    expect(controller.enableCalls, [CameraLens.back, CameraLens.front]);
    expect(cubit.state.selectedLens, CameraLens.front);
    expect(cubit.state.status, CameraStatus.enabled);

    await cubit.close();
  });

  test('suspends automatically but preserves manual power preference', () async {
    final controller = FakeCameraController();
    final cubit = CameraCubit(controller);
    await cubit.init();

    await cubit.setSurfaceActive(active: false);
    expect(controller.disableCalls, 1);
    expect(cubit.state.status, CameraStatus.disabled);
    expect(cubit.state.requestedEnabled, isTrue);

    await cubit.setSurfaceActive(active: true);
    expect(controller.enableCalls, [CameraLens.back, CameraLens.back]);

    await cubit.disableCamera();
    await cubit.setSurfaceActive(active: false);
    await cubit.setSurfaceActive(active: true);

    expect(cubit.state.requestedEnabled, isFalse);
    expect(cubit.state.status, CameraStatus.disabled);
    expect(controller.enableCalls, [CameraLens.back, CameraLens.back]);

    await cubit.close();
  });

  test('exposes permission failure and supports retry', () async {
    final controller = FakeCameraController(
      initFailure: const PermissionDeniedFailure(),
    );
    final cubit = CameraCubit(controller);

    await cubit.init();
    expect(cubit.state.status, CameraStatus.failure);
    expect(cubit.state.failure, isA<PermissionDeniedFailure>());

    controller.initFailure = null;
    await cubit.init();

    expect(cubit.state.status, CameraStatus.enabled);
    expect(controller.initCalls, 2);

    await cubit.close();
  });
}
