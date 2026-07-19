import 'dart:math' as math;

/// Resolution-independent detection bounds in the observed image.
final class NormalizedBox {
  /// Creates normalized bounds with ordered horizontal and vertical edges.
  const NormalizedBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(
         left >= 0 && left <= 1,
         'Left must be normalized.',
       ),
       assert(
         top >= 0 && top <= 1,
         'Top must be normalized.',
       ),
       assert(
         right >= 0 && right <= 1,
         'Right must be normalized.',
       ),
       assert(
         bottom >= 0 && bottom <= 1,
         'Bottom must be normalized.',
       ),
       assert(right >= left, 'Right must not precede left.'),
       assert(bottom >= top, 'Bottom must not precede top.');

  /// The left edge as a fraction of image width.
  final double left;

  /// The top edge as a fraction of image height.
  final double top;

  /// The right edge as a fraction of image width.
  final double right;

  /// The bottom edge as a fraction of image height.
  final double bottom;

  /// The box width as a fraction of image width.
  double get width => right - left;

  /// The box height as a fraction of image height.
  double get height => bottom - top;

  /// The horizontal center as a fraction of image width.
  double get centerX => left + width / 2;

  /// The vertical center as a fraction of image height.
  double get centerY => top + height / 2;

  /// The normalized area occupied by the box.
  double get area => width * height;

  /// Returns the intersection-over-union overlap with [other].
  double intersectionOverUnion(NormalizedBox other) {
    final intersectionWidth = math.max(
      0,
      math.min(right, other.right) - math.max(left, other.left),
    );
    final intersectionHeight = math.max(
      0,
      math.min(bottom, other.bottom) - math.max(top, other.top),
    );
    final intersectionArea = intersectionWidth * intersectionHeight;
    final unionArea = area + other.area - intersectionArea;
    if (unionArea == 0) {
      return 0;
    }
    return intersectionArea / unionArea;
  }
}
