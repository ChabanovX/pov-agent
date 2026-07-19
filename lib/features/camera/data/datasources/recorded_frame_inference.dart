import 'dart:typed_data';

import 'package:pov_agent/features/camera/application/models/observation_configuration.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// The raw native inference boundary for encoded recorded frames.
abstract interface class RecordedFrameInference {
  /// Loads the configured native model.
  Future<void> load();

  /// Runs native inference over [encodedImage].
  Future<Map<String, dynamic>> predict(Uint8List encodedImage);

  /// Releases the native inference runtime.
  Future<void> close();
}

/// Native single-image YOLO runtime used by deterministic recorded-frame tests.
final class UltralyticsRecordedFrameInference implements RecordedFrameInference {
  /// Creates an Ultralytics runtime with [configuration].
  UltralyticsRecordedFrameInference({
    this.configuration = ObservationConfiguration.milestoneOne,
  });

  /// The model and inference configuration used by this runtime.
  final ObservationConfiguration configuration;
  YOLO? _yolo;

  @override
  Future<void> load() async {
    final yolo = _yolo ??= YOLO(
      modelPath: configuration.modelPath,
      task: YOLOTask.detect,
      useGpu: configuration.useGpu,
      useMultiInstance: true,
    );
    final loaded = await yolo.loadModel();
    if (!loaded) {
      throw ModelLoadingException(
        'The ${configuration.modelPath} model did not report a successful load.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> predict(Uint8List encodedImage) {
    final yolo = _yolo;
    if (yolo == null) {
      throw StateError('The recorded-frame YOLO runtime has not been loaded.');
    }
    return yolo.predict(
      encodedImage,
      confidenceThreshold: configuration.confidenceThreshold,
      iouThreshold: configuration.iouThreshold,
    );
  }

  @override
  Future<void> close() async {
    final yolo = _yolo;
    _yolo = null;
    await yolo?.dispose();
  }
}
