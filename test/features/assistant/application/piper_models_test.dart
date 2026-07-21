import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/piper_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';

void main() {
  test('verified bundle is an immutable application value', () {
    const first = _bundle;
    const same = _bundle;
    const other = VerifiedPiperModelBundle(
      modelId: 'piper-ljspeech',
      revision: 'other-revision',
      bundleDirectoryPath: '/models/piper',
      modelFilePath: '/models/piper/voice.onnx',
      tokensFilePath: '/models/piper/tokens.txt',
      espeakDataDirectoryPath: '/models/piper/espeak-ng-data',
      extractedByteSize: 37347875,
      extractedFileCount: 359,
      bundleTreeSha256: 'verified-tree-digest',
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(other));
  });

  test('runtime policy has value equality and rejects invalid const inputs', () {
    const first = PiperRuntimeConfiguration(
      provider: 'cpu',
      threadCount: 1,
      speakerId: 0,
      noiseScale: 0.667,
      noiseScaleW: 0.8,
      lengthScale: 1,
      speed: 1,
      silenceScale: 0.2,
      maxSentences: 1,
      debug: false,
    );
    const same = PiperRuntimeConfiguration(
      provider: 'cpu',
      threadCount: 1,
      speakerId: 0,
      noiseScale: 0.667,
      noiseScaleW: 0.8,
      lengthScale: 1,
      speed: 1,
      silenceScale: 0.2,
      maxSentences: 1,
      debug: false,
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(
      () => PiperRuntimeConfiguration(
        provider: 'cpu',
        threadCount: 0,
        speakerId: 0,
        noiseScale: 0.667,
        noiseScaleW: 0.8,
        lengthScale: 1,
        speed: 1,
        silenceScale: 0.2,
        maxSentences: 1,
        debug: false,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}

const _bundle = VerifiedPiperModelBundle(
  modelId: 'piper-ljspeech',
  revision: 'tts-models',
  bundleDirectoryPath: '/models/piper',
  modelFilePath: '/models/piper/voice.onnx',
  tokensFilePath: '/models/piper/tokens.txt',
  espeakDataDirectoryPath: '/models/piper/espeak-ng-data',
  extractedByteSize: 37347875,
  extractedFileCount: 359,
  bundleTreeSha256: 'verified-tree-digest',
);
