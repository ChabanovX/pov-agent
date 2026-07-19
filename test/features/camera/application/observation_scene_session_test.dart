import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

import '../../../support/fake_camera_controller.dart';

void main() {
  test('starts explicitly and publishes only stable scene changes', () async {
    final controller = FakeCameraController();
    final session = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final changes = <SceneSnapshot>[];
    final subscription = session.changes.listen(changes.add);

    _emitFrames(controller, const [_person], count: 3);
    expect(session.current, const SceneSnapshot.empty());
    expect(changes, isEmpty);

    session.start();
    controller
      ..emit(const ObservationModelReady())
      ..emit(const ObservationModelDownloadProgressed(0.5));
    _emitFrames(controller, const [_person], count: 3);

    expect(changes, hasLength(1));
    expect(session.current, changes.single);
    expect(session.current.objects, hasLength(1));
    expect(session.current.objects.single.label, 'person');
    expect(session.current.objects.single.region, SceneRegion.leftTop);

    _emitFrames(controller, const [_person], count: 4);
    expect(changes, hasLength(1));

    await session.close();
    await subscription.cancel();
    await controller.close();
  });

  test('reset events clear identity without duplicate empty updates', () async {
    final controller = FakeCameraController();
    final session = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    )..start();
    final changes = <SceneSnapshot>[];
    final subscription = session.changes.listen(changes.add);

    controller.emit(const ObservationModelReady());
    _emitFrames(controller, const [_person], count: 2);
    controller.emit(const ObservationModelPreparing());
    expect(changes, isEmpty);

    controller.emit(const ObservationModelReady());
    _emitFrames(controller, const [_person], count: 3);
    final firstId = session.current.objects.single.id;
    controller
      ..emit(const ObservationModelPreparing())
      ..emit(const ObservationModelPreparing());
    expect(changes, hasLength(2));
    expect(changes.last, const SceneSnapshot.empty());

    controller.emit(const ObservationModelReady());
    _emitFrames(controller, const [_person], count: 3);
    final secondId = session.current.objects.single.id;
    expect(secondId, greaterThan(firstId));
    controller.emit(
      const ObservationFailed(NetworkFailure(code: 'model_failed')),
    );

    _emitFrames(controller, const [_person], count: 3);
    expect(session.current, const SceneSnapshot.empty());
    controller.emit(const ObservationModelReady());
    _emitFrames(controller, const [_person], count: 3);
    final thirdId = session.current.objects.single.id;
    expect(thirdId, greaterThan(secondId));
    controller.emit(
      const ObservationInferenceFailed(
        DeviceUnavailableFailure(code: 'inference_failed'),
      ),
    );

    expect(
      changes.map((snapshot) => snapshot.objects.isEmpty),
      [false, true, false, true, false, true],
    );
    expect(session.current, const SceneSnapshot.empty());

    await session.close();
    await subscription.cancel();
    await controller.close();
  });

  test('source discontinuity resets identity without reusing an ID', () async {
    final controller = FakeCameraController();
    final session = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    )..start();
    final changes = <SceneSnapshot>[];
    final subscription = session.changes.listen(changes.add);

    controller.emit(const ObservationModelReady());
    _emitFrames(controller, const [_person], count: 3);
    final firstId = session.current.objects.single.id;

    controller.emit(const ObservationSourceDiscontinuity());
    expect(session.current, const SceneSnapshot.empty());
    _emitFrames(controller, const [_person], count: 3);
    final secondId = session.current.objects.single.id;

    expect(secondId, greaterThan(firstId));
    expect(
      changes.map((snapshot) => snapshot.isEmpty),
      [false, true, false],
    );

    await session.close();
    await subscription.cancel();
    await controller.close();
  });

  test('start and close are idempotent and close stops event handling', () async {
    final controller = FakeCameraController();
    final session = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );
    final changes = <SceneSnapshot>[];
    var changesCompleted = false;
    final subscription = session.changes.listen(
      changes.add,
      onDone: () => changesCompleted = true,
    );

    session
      ..start()
      ..start();
    controller.emit(const ObservationModelReady());
    _emitFrames(controller, const [_person], count: 3);
    expect(changes, hasLength(1));
    final sceneBeforeClose = session.current;

    final firstClose = session.close();
    final secondClose = session.close();
    expect(identical(firstClose, secondClose), isTrue);
    await Future.wait([firstClose, secondClose]);

    expect(changesCompleted, isTrue);
    expect(controller.closeCalls, 0);
    controller.emit(const ObservationModelPreparing());
    _emitFrames(controller, const [_person], count: 3);
    expect(session.current, sceneBeforeClose);
    expect(changes, hasLength(1));
    expect(session.start, throwsStateError);

    await subscription.cancel();
    await controller.close();
  });

  test('rejects a controller whose event stream is not broadcast', () async {
    final controller = FakeCameraController(broadcastEvents: false);
    final session = ObservationSceneSession(
      controller: controller,
      stabilizer: SceneStabilizer(),
    );

    expect(
      session.start,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('must be a broadcast stream'),
        ),
      ),
    );
    expect(session.current, const SceneSnapshot.empty());

    final controllerEventsComplete = expectLater(
      controller.events,
      emitsDone,
    );
    await session.close();
    await controller.close();
    await controllerEventsComplete;
  });
}

void _emitFrames(
  FakeCameraController controller,
  List<Detection> detections, {
  required int count,
}) {
  for (var frame = 0; frame < count; frame += 1) {
    controller.emit(
      ObservationDetectionsUpdated(
        detections: detections,
        observedAt: DateTime.utc(2026, 7, 19, 12, 0, frame),
      ),
    );
  }
}

const _person = Detection(
  classId: 0,
  label: 'person',
  confidence: 0.9,
  box: NormalizedBox(left: 0.05, top: 0.05, right: 0.25, bottom: 0.25),
);
