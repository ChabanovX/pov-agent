/// Resolution-independent detection bounds in the observed image.
final class NormalizedBox {
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

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;

  double get height => bottom - top;
}
