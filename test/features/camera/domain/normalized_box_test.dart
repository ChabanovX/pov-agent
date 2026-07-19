import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';

void main() {
  test('derives center and area from normalized edges', () {
    const box = NormalizedBox(
      left: 0.1,
      top: 0.2,
      right: 0.5,
      bottom: 0.8,
    );

    expect(box.centerX, closeTo(0.3, 0.0000001));
    expect(box.centerY, closeTo(0.5, 0.0000001));
    expect(box.area, closeTo(0.24, 0.0000001));
  });

  test('computes intersection over union', () {
    const left = NormalizedBox(left: 0, top: 0, right: 0.75, bottom: 1);
    const right = NormalizedBox(left: 0.25, top: 0, right: 1, bottom: 1);

    expect(left.intersectionOverUnion(right), 0.5);
    expect(right.intersectionOverUnion(left), 0.5);
  });

  test('returns zero overlap for disjoint and zero-area boxes', () {
    const left = NormalizedBox(left: 0, top: 0, right: 0.2, bottom: 0.2);
    const right = NormalizedBox(left: 0.8, top: 0.8, right: 1, bottom: 1);
    const point = NormalizedBox(left: 0.5, top: 0.5, right: 0.5, bottom: 0.5);

    expect(left.intersectionOverUnion(right), 0);
    expect(point.intersectionOverUnion(point), 0);
  });
}
