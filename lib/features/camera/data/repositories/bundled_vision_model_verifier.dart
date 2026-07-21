import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:pov_agent/features/camera/application/models/verified_vision_model_artifact.dart';
import 'package:pov_agent/features/camera/application/models/vision_model_manifest.dart';
import 'package:pov_agent/features/camera/application/ports/vision_model_verifier.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Selects the checksum-pinned YOLO asset bundled for [platform].
VisionModelManifest bundledVisionManifestFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => VisionModelManifest(
      modelId: 'yolo26n',
      revision: 'ultralytics-yolo-0.6.10-bundle-v1',
      assetPath: 'assets/models/yolo26n.mlpackage.zip',
      byteSize: 2330303,
      sha256: '77a3ee3f41beefdf4cc54a194bbc3f0d0101c1cf32f8084caeb257c01c57b2e5',
    ),
    TargetPlatform.android || TargetPlatform.linux || TargetPlatform.windows => VisionModelManifest(
      modelId: 'yolo26n',
      revision: 'ultralytics-yolo-0.6.10-bundle-v1',
      assetPath: 'assets/models/yolo26n_w8a32.tflite',
      byteSize: 2875544,
      sha256: '293074598c5f39b70d18ea9088bb0153ccc674310659d165d6d608f825b255ef',
    ),
    TargetPlatform.fuchsia => throw UnsupportedError(
      'No bundled YOLO artifact is configured for Fuchsia.',
    ),
  };
}

/// Verifies one immutable YOLO asset shipped inside the application bundle.
///
/// This boundary never downloads or loads the native inference runtime. It
/// only proves that the platform-specific bytes match the receipt fingerprint
/// before the root router may open the application shell.
final class BundledVisionModelVerifier implements VisionModelVerifier {
  /// Creates a verifier from an explicit asset bundle and pinned manifest.
  const BundledVisionModelVerifier({
    required this.assetBundle,
    required this.manifest,
  });

  /// Bundle containing the platform-selected model asset.
  final AssetBundle assetBundle;

  /// Integrity metadata included in the model-pack fingerprint.
  final VisionModelManifest manifest;

  @override
  Future<AppResult<VerifiedVisionModelArtifact>> verify() async {
    Uint8List bytes;
    try {
      final data = await assetBundle.load(manifest.assetPath);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object catch (error, stackTrace) {
      return AppError(
        CacheFailure(
          code: 'vision_model_asset_unavailable',
          message: 'The bundled vision model could not be read.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    if (bytes.length != manifest.byteSize) {
      return const AppError(
        ValidationFailure(code: 'vision_model_integrity'),
      );
    }
    final digest = await Isolate.run(
      () => sha256.convert(bytes).toString(),
    );
    if (digest != manifest.sha256) {
      return const AppError(
        ValidationFailure(code: 'vision_model_integrity'),
      );
    }
    return AppSuccess(
      VerifiedVisionModelArtifact(
        modelId: manifest.modelId,
        revision: manifest.revision,
        assetPath: manifest.assetPath,
        byteSize: manifest.byteSize,
        sha256: manifest.sha256,
      ),
    );
  }
}
