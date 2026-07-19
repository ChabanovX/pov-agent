import 'package:meta/meta.dart';
import 'package:pov_agent/shared/domain/tracked_object.dart';

/// The immutable stable objects currently present in the scene.
@immutable
final class SceneSnapshot {
  /// Creates a snapshot in canonical ascending object-ID order.
  factory SceneSnapshot({required Iterable<TrackedObject> objects}) {
    final sortedObjects = List<TrackedObject>.of(objects)..sort((left, right) => left.id.compareTo(right.id));
    assert(
      _hasUniqueIds(sortedObjects),
      'A scene snapshot cannot contain duplicate object IDs.',
    );
    return SceneSnapshot._(List<TrackedObject>.unmodifiable(sortedObjects));
  }

  /// Creates the canonical scene with no stable objects.
  const SceneSnapshot.empty() : objects = const <TrackedObject>[];

  const SceneSnapshot._(this.objects);

  /// Stable objects in ascending [TrackedObject.id] order.
  final List<TrackedObject> objects;

  /// Whether the scene contains no stable objects.
  bool get isEmpty => objects.isEmpty;

  /// Whether the scene contains at least one stable object.
  bool get isNotEmpty => objects.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SceneSnapshot || objects.length != other.objects.length) {
      return false;
    }
    for (var index = 0; index < objects.length; index += 1) {
      if (objects[index] != other.objects[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(objects);
}

bool _hasUniqueIds(List<TrackedObject> objects) {
  for (var index = 1; index < objects.length; index += 1) {
    if (objects[index - 1].id == objects[index].id) {
      return false;
    }
  }
  return true;
}
