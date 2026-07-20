import 'package:meta/meta.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';

/// One completed automatic comment and the scene used to generate it.
@immutable
final class ObserverComment {
  /// Creates a committed observer comment.
  ObserverComment({required this.scene, required String text}) : text = _requireText(text);

  /// The stable scene sampled when generation began.
  final SceneSnapshot scene;

  /// The completed visible comment.
  final String text;
}

String _requireText(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'text', 'A comment must not be empty.');
  }
  return normalized;
}
