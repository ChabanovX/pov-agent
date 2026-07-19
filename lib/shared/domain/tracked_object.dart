import 'package:meta/meta.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';

/// A stable scene object identified for the current runtime session.
@immutable
final class TrackedObject {
  /// Creates a stable object with its coarse scene [region].
  const TrackedObject({
    required this.id,
    required this.classId,
    required this.label,
    required this.region,
  });

  /// The monotonic identifier assigned within the current runtime session.
  final int id;

  /// The model's numeric class identifier.
  final int classId;

  /// The model's human-readable class label.
  final String label;

  /// The object's current coarse position in the scene.
  final SceneRegion region;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TrackedObject &&
            id == other.id &&
            classId == other.classId &&
            label == other.label &&
            region == other.region;
  }

  @override
  int get hashCode => Object.hash(id, classId, label, region);
}
