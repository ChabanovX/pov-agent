import 'dart:typed_data';

import 'package:some_camera_with_llm/core/errors/failure_mapper.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/recorded_frame_detector.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:some_camera_with_llm/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_snapshot.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// A function that returns the current UTC time.
typedef UtcNow = DateTime Function();

/// A detector that maps raw recorded-frame inference at the data boundary.
final class RecordedFrameDetectorImpl implements RecordedFrameDetector {
  /// Creates a detector from its native inference and mapping dependencies.
  RecordedFrameDetectorImpl(
    this._inference,
    this._resultMapper,
    this._failureMapper, {
    UtcNow? utcNow,
  }) : _utcNow = utcNow ?? _defaultUtcNow;

  final RecordedFrameInference _inference;
  final YoloResultMapper _resultMapper;
  final FailureMapper _failureMapper;
  final UtcNow _utcNow;

  @override
  Future<AppResult<void>> load() async {
    try {
      await _inference.load();
      return const AppSuccess<void>(null);
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(_failureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<AppResult<ObservationSnapshot>> detect(Uint8List encodedImage) async {
    try {
      final raw = await _inference.predict(encodedImage);
      return AppSuccess(
        _resultMapper.snapshotFromRaw(raw, observedAt: _utcNow()),
      );
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(_failureMapper.map(error, stackTrace));
    }
  }

  @override
  Future<void> close() => _inference.close();
}

DateTime _defaultUtcNow() => DateTime.now().toUtc();
