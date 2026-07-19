import 'dart:async';

import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

/// Publishes stable scene changes for one observation-controller session.
///
/// Construction is side-effect free. [start] owns the subscription to
/// [ObservationController.events], while [close] cancels that subscription and
/// closes [changes]. The observation controller itself remains owned by app
/// composition and is never started or closed here.
final class ObservationSceneSession implements SceneSource {
  /// Creates an inert scene session backed by [controller] and [stabilizer].
  factory ObservationSceneSession({
    required ObservationController controller,
    required SceneStabilizer stabilizer,
  }) {
    return ObservationSceneSession._(
      controller,
      stabilizer,
      stabilizer.current,
    );
  }

  ObservationSceneSession._(
    this._controller,
    this._stabilizer,
    this._lastPublishedSnapshot,
  );

  final ObservationController _controller;
  final SceneStabilizer _stabilizer;
  final StreamController<SceneSnapshot> _changesController = StreamController<SceneSnapshot>.broadcast(sync: true);

  SceneSnapshot _lastPublishedSnapshot;
  bool _modelReady = false;
  // The session owns this subscription and cancels it during close.
  // ignore: cancel_subscriptions
  StreamSubscription<ObservationEvent>? _observationSubscription;
  Future<void>? _closeTask;
  _SceneSessionPhase _phase = _SceneSessionPhase.idle;

  @override
  SceneSnapshot get current => _stabilizer.current;

  @override
  Stream<SceneSnapshot> get changes => _changesController.stream;

  /// Starts consuming observation events.
  ///
  /// Repeated calls while running are ignored. Event handling is synchronous,
  /// so each detection frame is fully reconciled before the next event can
  /// mutate the stabilizer. Starting after shutdown has begun throws a
  /// [StateError].
  void start() {
    if (_phase == _SceneSessionPhase.running) return;
    if (_phase != _SceneSessionPhase.idle) {
      throw StateError('ObservationSceneSession cannot restart after close.');
    }

    _phase = _SceneSessionPhase.running;
    try {
      final events = _controller.events;
      if (!events.isBroadcast) {
        throw StateError(
          'ObservationController.events must be a broadcast stream.',
        );
      }
      _observationSubscription = events.listen(
        _processObservationEvent,
      );
    } on Object {
      _phase = _SceneSessionPhase.idle;
      rethrow;
    }
  }

  void _processObservationEvent(ObservationEvent event) {
    if (_phase != _SceneSessionPhase.running) return;

    final SceneSnapshot? update;
    switch (event) {
      case ObservationModelReady():
        _modelReady = true;
        update = null;
      case ObservationDetectionsUpdated(:final detections):
        update = _modelReady ? _stabilizer.processFrame(detections) : null;
      case ObservationModelPreparing() || ObservationFailed():
        _modelReady = false;
        update = _stabilizer.reset();
      case ObservationSourceDiscontinuity() || ObservationInferenceFailed():
        update = _stabilizer.reset();
      default:
        update = null;
    }
    _publishIfChanged(update);
  }

  void _publishIfChanged(SceneSnapshot? update) {
    if (update == null || update == _lastPublishedSnapshot) return;
    _lastPublishedSnapshot = update;
    _changesController.add(update);
  }

  /// Stops event consumption and closes the session-owned output stream.
  ///
  /// Shutdown is idempotent, including overlapping calls. It does not close the
  /// injected [ObservationController].
  Future<void> close() {
    final existingTask = _closeTask;
    if (existingTask != null) return existingTask;

    _phase = _SceneSessionPhase.closing;
    final task = _closeOwnedResources();
    _closeTask = task;
    return task;
  }

  Future<void> _closeOwnedResources() async {
    final subscription = _observationSubscription;
    try {
      if (subscription != null) await subscription.cancel();
    } finally {
      _observationSubscription = null;
      await _changesController.close();
      _phase = _SceneSessionPhase.closed;
    }
  }
}

enum _SceneSessionPhase { idle, running, closing, closed }
