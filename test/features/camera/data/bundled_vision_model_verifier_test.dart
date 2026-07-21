import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/verified_vision_model_artifact.dart';
import 'package:pov_agent/features/camera/application/models/vision_model_manifest.dart';
import 'package:pov_agent/features/camera/data/repositories/bundled_vision_model_verifier.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verifies the committed iOS and Android YOLO assets', () async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      final manifest = bundledVisionManifestFor(platform);
      final verifier = BundledVisionModelVerifier(
        assetBundle: rootBundle,
        manifest: manifest,
      );

      final result = await verifier.verify();

      expect(
        result,
        isA<AppSuccess<VerifiedVisionModelArtifact>>().having(
          (success) => success.value.assetPath,
          'asset path',
          manifest.assetPath,
        ),
      );
    }
  });

  test('rejects bundled bytes that differ from the pinned digest', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final manifest = VisionModelManifest(
      modelId: 'test-yolo',
      revision: 'test-revision',
      assetPath: 'assets/models/test-yolo.tflite',
      byteSize: bytes.length,
      sha256: sha256.convert([4, 3, 2, 1]).toString(),
    );
    final verifier = BundledVisionModelVerifier(
      assetBundle: _MemoryAssetBundle({manifest.assetPath: bytes}),
      manifest: manifest,
    );

    final result = await verifier.verify();

    expect(
      result,
      isA<AppError<VerifiedVisionModelArtifact>>().having(
        (error) => error.failure,
        'failure',
        isA<ValidationFailure>().having(
          (failure) => failure.code,
          'code',
          'vision_model_integrity',
        ),
      ),
    );
  });

  test('normalizes a missing bundle asset before leaving data', () async {
    final manifest = VisionModelManifest(
      modelId: 'test-yolo',
      revision: 'test-revision',
      assetPath: 'assets/models/missing.tflite',
      byteSize: 1,
      sha256: '0' * 64,
    );
    final verifier = BundledVisionModelVerifier(
      assetBundle: _MemoryAssetBundle(const {}),
      manifest: manifest,
    );

    final result = await verifier.verify();

    expect(
      result,
      isA<AppError<VerifiedVisionModelArtifact>>().having(
        (error) => error.failure.code,
        'failure code',
        'vision_model_asset_unavailable',
      ),
    );
  });
}

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Missing asset: $key');
    return ByteData.sublistView(bytes);
  }
}
