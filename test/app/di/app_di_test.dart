import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await appDependencies.reset(dispose: false);
  });

  test('registers the selected adapter under its surface contracts', () async {
    final runtime = configureDependencies();
    try {
      final controller = appDependencies<ObservationController>();

      if (CompilationConstants.usesRecordedVideo) {
        final adapter = appDependencies<RecordedObservationAdapter>();
        expect(controller, same(adapter));
        expect(
          appDependencies<RecordedObservationFrameSource>(),
          same(adapter),
        );
        expect(
          appDependencies.isRegistered<YoloObservationAdapter>(),
          isFalse,
        );
      } else {
        final adapter = appDependencies<YoloObservationAdapter>();
        expect(controller, same(adapter));
        expect(
          appDependencies.isRegistered<RecordedObservationAdapter>(),
          isFalse,
        );
        expect(
          appDependencies.isRegistered<RecordedObservationFrameSource>(),
          isFalse,
        );
      }
    } finally {
      await runtime.close();
    }
  });
}
