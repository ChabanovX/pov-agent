/// A validated detection parsed from a YOLO plugin payload.
final class YoloDetectionDto {
  /// Creates a validated detection transport object.
  const YoloDetectionDto({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// The native model class identifier.
  final int classId;

  /// The native model class label.
  final String label;

  /// The normalized detection confidence.
  final double confidence;

  /// The normalized left edge.
  final double left;

  /// The normalized top edge.
  final double top;

  /// The normalized right edge.
  final double right;

  /// The normalized bottom edge.
  final double bottom;

  /// A validated detection parsed from [map], or `null` if malformed.
  ///
  /// Finite confidence and coordinate values are clamped to the normalized
  /// range; invalid identifiers, labels, or inverted bounds are rejected.
  static YoloDetectionDto? tryFromMap(Map<dynamic, dynamic> map) {
    final classId = map['classIndex'];
    final label = map['className'];
    final confidence = map['confidence'];
    final normalizedBox = map['normalizedBox'];
    if (classId is! num ||
        !classId.isFinite ||
        classId < 0 ||
        label is! String ||
        label.trim().isEmpty ||
        confidence is! num ||
        !confidence.isFinite ||
        normalizedBox is! Map) {
      return null;
    }

    final left = _coordinate(normalizedBox['left']);
    final top = _coordinate(normalizedBox['top']);
    final right = _coordinate(normalizedBox['right']);
    final bottom = _coordinate(normalizedBox['bottom']);
    if (left == null || top == null || right == null || bottom == null || right < left || bottom < top) {
      return null;
    }

    return YoloDetectionDto(
      classId: classId.toInt(),
      label: label.trim(),
      confidence: confidence.toDouble().clamp(0, 1).toDouble(),
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }
}

double? _coordinate(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble().clamp(0, 1).toDouble();
}
