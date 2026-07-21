import 'package:pov_agent/features/assistant/data/datasources/model_bundle_extractor.dart';

/// Piper compatibility seam for the shared verified-bundle extractor.
abstract interface class PiperBundleExtractor implements ModelBundleExtractor {}

/// Adapts shared isolate extraction to the existing Piper composition API.
final class IsolatePiperBundleExtractor implements PiperBundleExtractor {
  /// Creates the production Piper archive extractor.
  const IsolatePiperBundleExtractor();

  static const _delegate = IsolateModelBundleExtractor();

  @override
  Future<void> extract({
    required String archivePath,
    required String destinationPath,
    required String temporaryTarPath,
    required int expectedTarByteSize,
  }) {
    return _delegate.extract(
      archivePath: archivePath,
      destinationPath: destinationPath,
      temporaryTarPath: temporaryTarPath,
      expectedTarByteSize: expectedTarByteSize,
    );
  }
}
