import 'dart:typed_data';

import 'package:pov_agent/features/camera/domain/entities/observation_snapshot.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// A detector that runs the production model over encoded recorded frames.
abstract interface class RecordedFrameDetector {
  /// Loads the inference model, normalizing expected failures.
  Future<AppResult<void>> load();

  /// Detects objects in [encodedImage] and returns an owned snapshot.
  Future<AppResult<ObservationSnapshot>> detect(Uint8List encodedImage);

  /// Releases the detector's native inference resources.
  Future<void> close();
}
