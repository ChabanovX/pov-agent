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
}
