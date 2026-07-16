import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/app/bootstrap/app_runtime.dart';
import 'package:some_camera_with_llm/features/camera/presentation/bloc/camera_bloc.dart';

import '../../support/fake_camera_controller.dart';

void main() {
  testWidgets('owns explicit camera startup and shutdown exactly once', (
    tester,
  ) async {
    final controller = FakeCameraController();
    final runtime = AppRuntime(
      cameraBloc: CameraBloc(controller),
      cameraPreview: const SizedBox.expand(),
    );

    expect(controller.initCalls, 0);
    expect(controller.closeCalls, 0);

    await runtime.start();
    await runtime.start();

    expect(controller.initCalls, 1);
    expect(controller.enableCalls, hasLength(1));

    await tester.runAsync(runtime.close);
    await tester.runAsync(runtime.close);

    expect(controller.closeCalls, 1);
  });
}
