import 'dart:typed_data';

import 'package:some_camera_with_llm/features/camera/application/models/observation_configuration.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

abstract interface class RecordedFrameInference {
  Future<void> load();

  Future<Map<String, dynamic>> predict(Uint8List encodedImage);

  Future<void> close();
}

/// Native single-image YOLO runtime used by deterministic recorded-frame tests.
final class UltralyticsRecordedFrameInference implements RecordedFrameInference {
  UltralyticsRecordedFrameInference({
    this.configuration = ObservationConfiguration.milestoneOne,
  }) : _yolo = YOLO(
         modelPath: configuration.modelPath,
         task: YOLOTask.detect,
         useGpu: configuration.useGpu,
         useMultiInstance: true,
       );

  final ObservationConfiguration configuration;
  final YOLO _yolo;

  @override
  Future<void> load() async {
    final loaded = await _yolo.loadModel();
    if (!loaded) {
      throw ModelLoadingException(
        'The ${configuration.modelPath} model did not report a successful load.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> predict(Uint8List encodedImage) {
    return _yolo.predict(
      encodedImage,
      confidenceThreshold: configuration.confidenceThreshold,
      iouThreshold: configuration.iouThreshold,
    );
  }

  @override
  Future<void> close() => _yolo.dispose();
}
