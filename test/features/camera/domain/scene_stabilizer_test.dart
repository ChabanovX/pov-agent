import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

void main() {
  group('SceneStabilizer', () {
    test('publishes appearance on the third presence in five frames', () {
      final stabilizer = SceneStabilizer();
      final detection = _detection();

      expect(stabilizer.processFrame([detection]), isNull);
      expect(stabilizer.processFrame([detection]), isNull);

      final appearance = stabilizer.processFrame([detection]);
      expect(appearance?.objects, hasLength(1));
      expect(appearance?.objects.single.id, 1);
      expect(appearance?.objects.single.region, SceneRegion.leftTop);
      expect(stabilizer.current, appearance);
    });

    test('promotes three non-consecutive hits in the rolling window', () {
      final stabilizer = SceneStabilizer();
      final detection = _detection();

      expect(stabilizer.processFrame([detection]), isNull);
      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.processFrame([detection]), isNull);
      expect(stabilizer.processFrame(const []), isNull);
      final appearance = stabilizer.processFrame([detection]);

      expect(appearance?.objects.single.id, 1);
    });

    test('does not flicker after one missed detection', () {
      final stabilizer = SceneStabilizer();
      final stable = _promote(stabilizer, _detection());

      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.current, stable);
      expect(stabilizer.processFrame([_detection()]), isNull);
    });

    test('removes an object on its third miss in the last five frames', () {
      final stabilizer = SceneStabilizer();
      final stable = _promote(stabilizer, _detection());

      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.current, stable);
      final disappearance = stabilizer.processFrame(const []);

      expect(disappearance, const SceneSnapshot.empty());
      expect(stabilizer.current, const SceneSnapshot.empty());
    });

    test('removes three non-consecutive misses in the rolling window', () {
      final stabilizer = SceneStabilizer();
      final detection = _detection();
      _promote(stabilizer, detection);

      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.processFrame([detection]), isNull);
      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.processFrame([detection]), isNull);
      final disappearance = stabilizer.processFrame(const []);

      expect(disappearance, const SceneSnapshot.empty());
    });

    test('preserves identity and confirms a region move three times', () {
      final stabilizer = SceneStabilizer();
      final initial = _promote(stabilizer, _detection());
      final movedDetection = _detection(left: 0.25, right: 0.45);

      expect(stabilizer.processFrame([movedDetection]), isNull);
      expect(stabilizer.processFrame([movedDetection]), isNull);
      final movement = stabilizer.processFrame([movedDetection]);

      expect(initial.objects.single.id, 1);
      expect(initial.objects.single.region, SceneRegion.leftTop);
      expect(movement?.objects.single.id, 1);
      expect(movement?.objects.single.region, SceneRegion.top);
    });

    test('does not publish alternating jitter across a region boundary', () {
      final stabilizer = SceneStabilizer();
      final leftOfBoundary = _detection(left: 0.13, right: 0.53);
      final rightOfBoundary = _detection(left: 0.14, right: 0.54);
      final initial = _promote(stabilizer, leftOfBoundary);

      for (var frame = 0; frame < 8; frame += 1) {
        final detection = frame.isEven ? rightOfBoundary : leftOfBoundary;
        expect(stabilizer.processFrame([detection]), isNull);
      }

      expect(stabilizer.current, initial);
      expect(stabilizer.current.objects.single.region, SceneRegion.leftTop);
    });

    test('keeps region evidence across misses without counting them', () {
      final stabilizer = SceneStabilizer();
      final movedDetection = _detection(left: 0.25, right: 0.45);
      _promote(stabilizer, _detection());

      expect(stabilizer.processFrame([movedDetection]), isNull);
      expect(stabilizer.processFrame(const []), isNull);
      expect(stabilizer.processFrame([movedDetection]), isNull);
      expect(stabilizer.processFrame(const []), isNull);
      final movement = stabilizer.processFrame([movedDetection]);

      expect(movement?.objects.single.id, 1);
      expect(movement?.objects.single.region, SceneRegion.top);
    });

    test('uses each matched box for the next match without scene noise', () {
      final stabilizer = SceneStabilizer();
      final initial = _promote(
        stabilizer,
        _detection(left: 0, right: 0.3, top: 0.1, bottom: 0.3),
      );
      final bridge = _detection(
        left: 0.08,
        right: 0.38,
        top: 0.1,
        bottom: 0.3,
      );
      final destination = _detection(
        left: 0.16,
        right: 0.46,
        top: 0.1,
        bottom: 0.3,
      );

      expect(stabilizer.processFrame([bridge]), isNull);
      expect(stabilizer.processFrame([destination]), isNull);
      expect(stabilizer.processFrame([destination]), isNull);
      expect(stabilizer.processFrame([destination]), isNull);
      expect(stabilizer.current, initial);
      expect(stabilizer.current.objects.single.id, 1);
    });

    test('does not publish same-region box or confidence jitter', () {
      final stabilizer = SceneStabilizer();
      final stable = _promote(stabilizer, _detection());

      final change = stabilizer.processFrame([
        _detection(confidence: 0.45, left: 0.21, right: 0.41),
      ]);

      expect(change, isNull);
      expect(stabilizer.current, stable);
    });

    test('matches an object at the inclusive IoU threshold', () {
      final stabilizer = SceneStabilizer();
      final first = _detection(left: 0, right: 0.75);
      final thresholdOverlap = _detection(left: 0.25, right: 1);

      expect(stabilizer.processFrame([first]), isNull);
      expect(stabilizer.processFrame([thresholdOverlap]), isNull);
      final appearance = stabilizer.processFrame([first]);

      expect(appearance?.objects.single.id, 1);
    });

    test('uses canonical detection order for deterministic IDs', () {
      final left = _detection(left: 0.05, right: 0.25);
      final right = _detection(left: 0.75, right: 0.95);
      final firstOrder = SceneStabilizer();
      final reversedOrder = SceneStabilizer();

      for (var frame = 0; frame < 3; frame += 1) {
        firstOrder.processFrame([left, right]);
        reversedOrder.processFrame([right, left]);
      }

      expect(firstOrder.current, reversedOrder.current);
      expect(
        firstOrder.current.objects.map((object) => object.region),
        [SceneRegion.leftTop, SceneRegion.rightTop],
      );
    });

    test('partitions matching by class before comparing overlap', () {
      final stabilizer = SceneStabilizer();
      final person = _detection(
        left: 0,
        right: 0.6,
      );
      final bus = _detection(
        classId: 5,
        label: 'bus',
        right: 0.8,
      );
      for (var frame = 0; frame < 3; frame += 1) {
        stabilizer.processFrame([person, bus]);
      }

      final update = stabilizer.processFrame([
        _detection(
          left: 0.15,
          right: 0.75,
        ),
        _detection(
          classId: 5,
          label: 'bus',
          left: 0.05,
          right: 0.65,
        ),
      ]);

      expect(update, isNull);
      expect(
        stabilizer.current.objects.map(
          (object) => (object.id, object.classId, object.label),
        ),
        [(1, 0, 'person'), (2, 5, 'bus')],
      );
    });

    test('handles a bounded dense same-class frame deterministically', () {
      final stabilizer = SceneStabilizer();
      final detections = List<Detection>.filled(
        80,
        _detection(),
      );

      expect(stabilizer.processFrame(detections), isNull);
      expect(stabilizer.processFrame(detections), isNull);
      final appearance = stabilizer.processFrame(detections);

      expect(appearance?.objects, hasLength(80));
      expect(
        appearance?.objects.map((object) => object.id),
        List<int>.generate(80, (index) => index + 1),
      );
      expect(stabilizer.processFrame(detections), isNull);
    });

    test('matches one detection to the lower-ID overlapping track only', () {
      final stabilizer = SceneStabilizer();
      final detection = _detection();

      stabilizer
        ..processFrame([detection, detection])
        ..processFrame([detection, detection]);
      final bothStable = stabilizer.processFrame([detection, detection]);
      expect(bothStable?.objects.map((object) => object.id), [1, 2]);

      expect(stabilizer.processFrame([detection]), isNull);
      expect(stabilizer.processFrame([detection]), isNull);
      final oneSurvivor = stabilizer.processFrame([detection]);

      expect(oneSurvivor?.objects.map((object) => object.id), [1]);
    });

    test('maximizes valid matches before total overlap', () {
      final stabilizer = SceneStabilizer();
      final first = _detection(right: 0.6);
      final second = _detection(left: 0.4, right: 0.8);
      final firstMoved = _detection(left: 0.07, right: 0.47);
      final secondMoved = _detection(left: 0.27, right: 0.67);

      for (var frame = 0; frame < 3; frame += 1) {
        stabilizer.processFrame([first, second]);
      }
      expect(stabilizer.current.objects.map((object) => object.id), [1, 2]);

      expect(stabilizer.processFrame([firstMoved, secondMoved]), isNull);
      expect(stabilizer.processFrame([firstMoved, secondMoved]), isNull);
      final movement = stabilizer.processFrame([firstMoved, secondMoved]);

      expect(movement?.objects.map((object) => object.id), [1, 2]);
      expect(
        movement?.objects.map((object) => object.region),
        [SceneRegion.leftTop, SceneRegion.top],
      );
    });

    test('preserves a stable track before a higher-overlap tentative track', () {
      final stabilizer = SceneStabilizer();
      final stableDetection = _detection(right: 0.6);
      final tentativeDetection = _detection(left: 0.34, right: 0.74);
      final sharedDetection = _detection(left: 0.32, right: 0.72);
      final stable = _promote(stabilizer, stableDetection);

      expect(
        stabilizer.processFrame([stableDetection, tentativeDetection]),
        isNull,
      );
      expect(stabilizer.processFrame([sharedDetection]), isNull);
      expect(stabilizer.processFrame([sharedDetection]), isNull);
      expect(stabilizer.processFrame([sharedDetection]), isNull);

      expect(stabilizer.current, stable);
      expect(stabilizer.current.objects.single.id, 1);
    });

    test('uses canonical pairing after a quantized overlap tie', () {
      final stabilizer = SceneStabilizer();
      final firstTrack = _detection(left: 0.1404, right: 0.5786);
      final secondTrack = _detection(left: 0.1667, right: 0.6049);
      final firstDetection = _detection(left: 0.0977, right: 0.7377);
      final secondDetection = _detection(left: 0.189, right: 0.5527);

      for (var frame = 0; frame < 3; frame += 1) {
        stabilizer.processFrame([firstTrack, secondTrack]);
      }
      expect(stabilizer.current.objects.map((object) => object.id), [1, 2]);

      expect(
        stabilizer.processFrame([firstDetection, secondDetection]),
        isNull,
      );
      expect(stabilizer.processFrame([firstDetection]), isNull);
      expect(stabilizer.processFrame([firstDetection]), isNull);
      final oneSurvivor = stabilizer.processFrame([firstDetection]);

      expect(oneSurvivor?.objects.map((object) => object.id), [1]);
    });

    test('assigns a new ID when overlap stays below the threshold', () {
      final stabilizer = SceneStabilizer();
      _promote(stabilizer, _detection(left: 0.05, right: 0.25));
      final replacement = _detection(left: 0.75, right: 0.95);

      expect(stabilizer.processFrame([replacement]), isNull);
      expect(stabilizer.processFrame([replacement]), isNull);
      final changed = stabilizer.processFrame([replacement]);

      expect(changed?.objects.single.id, 2);
      expect(changed?.objects.single.region, SceneRegion.rightTop);
    });

    test('reset clears evidence without reusing session IDs', () {
      final stabilizer = SceneStabilizer();
      _promote(stabilizer, _detection());

      expect(stabilizer.reset(), const SceneSnapshot.empty());
      expect(stabilizer.reset(), isNull);

      final next = _promote(stabilizer, _detection());
      expect(next.objects.single.id, 2);
    });

    test('reset silently discards tentative tracks', () {
      final stabilizer = SceneStabilizer();

      expect(stabilizer.processFrame([_detection()]), isNull);
      expect(stabilizer.reset(), isNull);
      final next = _promote(stabilizer, _detection());

      expect(next.objects.single.id, 2);
    });
  });
}

SceneSnapshot _promote(SceneStabilizer stabilizer, Detection detection) {
  stabilizer
    ..processFrame([detection])
    ..processFrame([detection]);
  return stabilizer.processFrame([detection])!;
}

Detection _detection({
  int classId = 0,
  String label = 'person',
  double confidence = 0.9,
  double left = 0.2,
  double top = 0.2,
  double right = 0.4,
  double bottom = 0.4,
}) {
  return Detection(
    classId: classId,
    label: label,
    confidence: confidence,
    box: NormalizedBox(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    ),
  );
}
