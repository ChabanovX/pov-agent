import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/di/assistant_build_configuration.dart';

void main() {
  test('pins the default artifact and decoding policy', () {
    final configuration = AssistantBuildConfiguration.fromEnvironment();

    expect(
      configuration.manifest.downloadUri.toString(),
      contains('272676c9e0eb9f33a7719ba3d27482fbb445e801'),
    );
    expect(configuration.manifest.modelId, 'unsloth/Qwen3-0.6B-GGUF');
    expect(configuration.manifest.filename, 'Qwen3-0.6B-Q4_K_M.gguf');
    expect(configuration.manifest.byteSize, 396705472);
    expect(
      configuration.manifest.sha256,
      'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a',
    );
    expect(configuration.manifest.license, 'Apache-2.0');
    expect(configuration.runtime.contextTokens, 2048);
    expect(configuration.runtime.batchTokens, 512);
    expect(configuration.runtime.threadCount, 4);
    expect(configuration.runtime.gpuLayers, 99);
    expect(configuration.manualOptions.maxTokens, 512);
    expect(configuration.manualOptions.temperature, 0.6);
    expect(configuration.manualOptions.topP, 0.95);
    expect(configuration.manualOptions.topK, 20);
    expect(configuration.commentOptions.maxTokens, 40);
    expect(configuration.commentOptions.temperature, 0.7);
    expect(configuration.commentOptions.topP, 0.8);
    expect(configuration.commentOptions.topK, 20);
  });

  test('pins the default offline Piper bundle and runtime policy', () {
    final configuration = AssistantBuildConfiguration.fromEnvironment();
    final manifest = configuration.piperManifest;

    expect(
      manifest.downloadUri.toString(),
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
    );
    expect(
      manifest.modelId,
      'k2-fsa/sherpa-onnx/vits-piper-en_US-ljspeech-medium-int8',
    );
    expect(manifest.revision, 'tts-models');
    expect(
      manifest.archiveFilename,
      'vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
    );
    expect(manifest.archiveByteSize, 21090429);
    expect(
      manifest.archiveSha256,
      '24dc3bd77dd48c291e52c297878d3437c9492f245d823d7f6a06c4bbb67f4b6b',
    );
    expect(manifest.expandedArchiveByteSize, 37662720);
    expect(manifest.extractedByteSize, 37347875);
    expect(manifest.extractedFileCount, 359);
    expect(
      manifest.bundleTreeSha256,
      'a38256a8fada764a1e7b450c5f307b7b5de159e137af1a6aae0b2326f355bc3b',
    );
    expect(manifest.archiveRoot, 'vits-piper-en_US-ljspeech-medium-int8');
    expect(manifest.modelFilename, 'en_US-ljspeech-medium.onnx');
    expect(manifest.tokensFilename, 'tokens.txt');
    expect(manifest.espeakDataDirectory, 'espeak-ng-data');
    expect(manifest.license, 'Public-Domain');
    expect(manifest.downloadReserveBytes, 33554432);
    expect(configuration.piperRuntime.provider, 'cpu');
    expect(configuration.piperRuntime.threadCount, 1);
    expect(configuration.piperRuntime.speakerId, 0);
    expect(configuration.piperRuntime.noiseScale, 0.667);
    expect(configuration.piperRuntime.noiseScaleW, 0.8);
    expect(configuration.piperRuntime.lengthScale, 1.0);
    expect(configuration.piperRuntime.speed, 1.0);
    expect(configuration.piperRuntime.silenceScale, 0.2);
    expect(configuration.piperRuntime.maxSentences, 1);
    expect(configuration.piperRuntime.debug, isFalse);
  });

  test('rejects malformed floating-point compile values', () {
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        manualTemperature: 'not-a-number',
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        commentTopP: 'Infinity',
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        contextTokens: 'not-an-integer',
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperSpeed: 'NaN',
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperModelArchiveSizeBytes: 'twenty-megabytes',
      ),
      throwsFormatException,
    );
  });

  test('rejects unsafe runtime and sampling combinations', () {
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        contextTokens: '512',
        batchTokens: '1024',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        randomSeed: '4294967296',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        manualMinP: '1.1',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        contextTokens: '511',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        gpuLayers: '2147483648',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperProvider: 'coreml',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperSpeakerId: '1',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperSpeed: '0',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperSilenceScale: '-0.1',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperNoiseScaleW: '-0.1',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperLengthScale: '0',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperMaxSentences: '0',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperDebug: 'FALSE',
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperModelArchiveSizeBytes: '9223372036854775807',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperModelExpandedArchiveSizeBytes: '0',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperModelArchiveSha256: 'not-a-digest',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        piperModelArchiveFilename: 'Qwen3-0.6B-Q4_K_M.gguf',
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        modelFilename: 'VOICE.EXTRACTING.TAR',
        piperModelArchiveRoot: 'voice',
      ),
      throwsArgumentError,
    );
  });
}
