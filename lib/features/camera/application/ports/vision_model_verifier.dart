import 'package:pov_agent/features/camera/application/models/verified_vision_model_artifact.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Verifies the platform-bundled vision artifact without camera acquisition.
// The boundary is injected independently from the camera runtime so setup can
// prove the artifact before presentation mounts a native surface.
// ignore: one_member_abstracts
abstract interface class VisionModelVerifier {
  /// Returns the pinned artifact only after its bytes pass integrity checks.
  Future<AppResult<VerifiedVisionModelArtifact>> verify();
}
