import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/tracked_object.dart';

void main() {
  group('SceneRegion', () {
    test('maps normalized points to all nine grid cells', () {
      const cases = <({double x, double y, SceneRegion expected})>[
        (x: 0.1, y: 0.1, expected: SceneRegion.leftTop),
        (x: 0.5, y: 0.1, expected: SceneRegion.top),
        (x: 0.9, y: 0.1, expected: SceneRegion.rightTop),
        (x: 0.1, y: 0.5, expected: SceneRegion.left),
        (x: 0.5, y: 0.5, expected: SceneRegion.center),
        (x: 0.9, y: 0.5, expected: SceneRegion.right),
        (x: 0.1, y: 0.9, expected: SceneRegion.leftBottom),
        (x: 0.5, y: 0.9, expected: SceneRegion.bottom),
        (x: 0.9, y: 0.9, expected: SceneRegion.rightBottom),
      ];

      for (final testCase in cases) {
        expect(
          SceneRegion.fromNormalizedPoint(x: testCase.x, y: testCase.y),
          testCase.expected,
        );
      }
    });

    test('assigns exact third boundaries to the following cell', () {
      expect(
        SceneRegion.fromNormalizedPoint(x: 1 / 3, y: 1 / 3),
        SceneRegion.center,
      );
      expect(
        SceneRegion.fromNormalizedPoint(x: 2 / 3, y: 2 / 3),
        SceneRegion.rightBottom,
      );
    });
  });

  group('SceneSnapshot', () {
    const first = TrackedObject(
      id: 1,
      classId: 0,
      label: 'person',
      region: SceneRegion.left,
    );
    const second = TrackedObject(
      id: 2,
      classId: 5,
      label: 'bus',
      region: SceneRegion.right,
    );

    test('stores objects immutably in canonical ID order', () {
      final snapshot = SceneSnapshot(objects: const [second, first]);

      expect(snapshot.objects, const [first, second]);
      expect(
        () => snapshot.objects.add(first),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('compares snapshots and tracked objects by value', () {
      final left = SceneSnapshot(objects: const [second, first]);
      final right = SceneSnapshot(objects: const [first, second]);

      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(const SceneSnapshot.empty(), SceneSnapshot(objects: const []));
    });
  });
}
