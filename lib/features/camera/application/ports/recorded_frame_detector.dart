import 'dart:typed_data';

import 'package:some_camera_with_llm/features/camera/domain/entities/observation_snapshot.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';

/// Runs the production model over encoded recorded frames without a camera.
abstract interface class RecordedFrameDetector {
  Future<AppResult<void>> load();

  Future<AppResult<ObservationSnapshot>> detect(Uint8List encodedImage);

  Future<void> close();
}
