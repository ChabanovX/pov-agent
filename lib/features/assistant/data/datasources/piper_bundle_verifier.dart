import 'package:pov_agent/features/assistant/data/datasources/model_bundle_verifier.dart';

/// Piper compatibility name for the shared canonical tree result.
typedef PiperBundleVerification = ModelBundleVerification;

/// Piper compatibility seam for the shared verified-bundle tree hasher.
abstract interface class PiperBundleVerifier implements ModelBundleVerifier {}

/// Adapts shared isolate verification to the existing Piper composition API.
final class IsolatePiperBundleVerifier implements PiperBundleVerifier {
  /// Creates the production Piper bundle verifier.
  const IsolatePiperBundleVerifier();

  static const _delegate = IsolateModelBundleVerifier();

  @override
  Future<PiperBundleVerification> verify(String bundleDirectoryPath) {
    return _delegate.verify(bundleDirectoryPath);
  }
}
