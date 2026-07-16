final class YoloDetectionDto {
  const YoloDetectionDto({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int classId;
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

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
