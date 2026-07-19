/// A coarse object position in a normalized 3×3 scene grid.
enum SceneRegion {
  /// The upper-left cell.
  leftTop,

  /// The upper-center cell.
  top,

  /// The upper-right cell.
  rightTop,

  /// The middle-left cell.
  left,

  /// The center cell.
  center,

  /// The middle-right cell.
  right,

  /// The lower-left cell.
  leftBottom,

  /// The lower-center cell.
  bottom,

  /// The lower-right cell.
  rightBottom;

  /// Locates a normalized point using half-open thirds on both axes.
  static SceneRegion fromNormalizedPoint({
    required double x,
    required double y,
  }) {
    assert(x >= 0 && x <= 1, 'The horizontal coordinate must be normalized.');
    assert(y >= 0 && y <= 1, 'The vertical coordinate must be normalized.');

    final column = x < 1 / 3
        ? 0
        : x < 2 / 3
        ? 1
        : 2;
    final row = y < 1 / 3
        ? 0
        : y < 2 / 3
        ? 1
        : 2;

    return switch ((row, column)) {
      (0, 0) => SceneRegion.leftTop,
      (0, 1) => SceneRegion.top,
      (0, 2) => SceneRegion.rightTop,
      (1, 0) => SceneRegion.left,
      (1, 1) => SceneRegion.center,
      (1, 2) => SceneRegion.right,
      (2, 0) => SceneRegion.leftBottom,
      (2, 1) => SceneRegion.bottom,
      (2, 2) => SceneRegion.rightBottom,
      _ => throw StateError('A 3×3 grid index must be between zero and two.'),
    };
  }
}
