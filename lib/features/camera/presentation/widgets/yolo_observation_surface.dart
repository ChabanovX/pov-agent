import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pov_agent/features/camera/application/models/observation_configuration.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// A live camera surface rendered by the native YOLO view.
///
/// Design decisions:
/// - App composition supplies adapter-owned state and callbacks so this
///   presentation widget does not depend on the feature's data layer.
final class YoloObservationSurface extends StatelessWidget {
  /// Creates a surface from dependencies supplied by app composition.
  const YoloObservationSurface({
    required this.configuration,
    required this.surfaceRevision,
    required this.desiredLens,
    required this.viewController,
    required this.onResults,
    required this.onPerformance,
    required this.onModelLoaded,
    required this.onModelError,
    super.key,
  });

  /// The model and inference settings applied to the native view.
  final ObservationConfiguration configuration;

  /// Changes whenever the native view must be recreated.
  final ValueListenable<int> surfaceRevision;

  /// Reads the lens that the next native view should attach.
  final ValueGetter<CameraLens> desiredLens;

  /// Controls the native view after it attaches.
  final YOLOViewController viewController;

  /// Receives native detection results.
  final ValueChanged<List<YOLOResult>> onResults;

  /// Receives native performance samples.
  final ValueChanged<YOLOPerformanceMetrics> onPerformance;

  /// Receives successful model attachment callbacks.
  final void Function({
    required int revision,
    required CameraLens attachedLens,
    required String modelPath,
  })
  onModelLoaded;

  /// Receives native model failures with their current stack trace.
  final void Function(Object error, StackTrace stackTrace) onModelError;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: surfaceRevision,
      builder: (context, revision, _) {
        final attachedLens = desiredLens();
        return YOLOView(
          key: ValueKey(('yolo-observation-surface', revision)),
          modelPath: configuration.modelPath,
          task: YOLOTask.detect,
          controller: viewController,
          cameraResolution: configuration.cameraResolution,
          confidenceThreshold: configuration.confidenceThreshold,
          iouThreshold: configuration.iouThreshold,
          useGpu: configuration.useGpu,
          lensFacing: switch (attachedLens) {
            CameraLens.back => LensFacing.back,
            CameraLens.front => LensFacing.front,
          },
          onResult: onResults,
          onPerformanceMetrics: onPerformance,
          onModelLoad: (modelPath, _) {
            onModelLoaded(
              revision: revision,
              attachedLens: attachedLens,
              modelPath: modelPath,
            );
          },
          onModelError: (error, _, _) {
            onModelError(error, StackTrace.current);
          },
        );
      },
    );
  }
}
