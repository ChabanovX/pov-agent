import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/recorded_frame_detector.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_snapshot.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// A function that returns the current UTC time.
@visibleForTesting
typedef UtcNow = DateTime Function();

/// A detector that maps raw recorded-frame inference at the data boundary.
final class RecordedFrameDetectorImpl implements RecordedFrameDetector {
  /// Creates a detector backed by [inference].
  RecordedFrameDetectorImpl(
    RecordedFrameInference inference, {
    @visibleForTesting UtcNow? utcNow,
  }) : _inference = inference,
       _utcNow = utcNow ?? _defaultUtcNow;

  final RecordedFrameInference _inference;
  final UtcNow _utcNow;

  @override
  Future<AppResult<void>> load() async {
    try {
      await _inference.load();
      return const AppSuccess<void>(null);
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(YoloFailureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<AppResult<ObservationSnapshot>> detect(Uint8List encodedImage) async {
    try {
      final raw = await _inference.predict(encodedImage);
      return AppSuccess(
        YoloResultMapper.snapshotFromRaw(raw, observedAt: _utcNow()),
      );
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(YoloFailureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<void> close() => _inference.close();
}

DateTime _defaultUtcNow() => DateTime.now().toUtc();
