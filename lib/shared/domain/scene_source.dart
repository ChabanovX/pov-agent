import 'package:pov_agent/shared/domain/scene_snapshot.dart';

/// Exposes the latest stable scene and subsequent semantic changes.
abstract interface class SceneSource {
  /// The latest stable scene, synchronously available to new consumers.
  SceneSnapshot get current;

  /// Stable scene changes in publication order.
  Stream<SceneSnapshot> get changes;
}
