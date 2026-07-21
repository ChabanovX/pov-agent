import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/di/assistant_build_configuration.dart';
import 'package:pov_agent/app/di/assistant_environment_values.dart';

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
    expect(configuration.dialogueOptions.maxTokens, 512);
    expect(configuration.dialogueOptions.temperature, 0.6);
    expect(configuration.dialogueOptions.topP, 0.95);
    expect(configuration.dialogueOptions.topK, 20);
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

  test('pins the default streaming ASR bundle and endpoint policy', () {
    final configuration = AssistantBuildConfiguration.fromEnvironment();
    final manifest = configuration.asrManifest;

    expect(
      manifest.downloadUri.toString(),
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      'sherpa-onnx-nemo-streaming-fast-conformer-ctc-en-80ms-int8.tar.bz2',
    );
    expect(manifest.revision, 'asr-models');
    expect(manifest.archiveByteSize, 99459493);
    expect(
      manifest.archiveSha256,
      '479759fbd5c69c909e7175d7773105a1bfabf82fa533de68c546c89d85f234e8',
    );
    expect(manifest.expandedArchiveByteSize, 132891648);
    expect(manifest.extractedByteSize, 132884963);
    expect(manifest.extractedFileCount, 6);
    expect(
      manifest.bundleTreeSha256,
      '8ec5fb017edb1fc389101bf235cbc13063185657b91752b9b17fa649eeade040',
    );
    expect(manifest.modelFilename, 'model.int8.onnx');
    expect(manifest.tokensFilename, 'tokens.txt');
    expect(manifest.license, 'NVIDIA-NGC-TOU');
    expect(configuration.asrRuntime.provider, 'cpu');
    expect(configuration.asrRuntime.threadCount, 2);
    expect(configuration.asrRuntime.sampleRateHz, 16000);
    expect(configuration.asrRuntime.featureDimension, 80);
    expect(configuration.asrRuntime.decodingMethod, 'greedy_search');
    expect(configuration.asrRuntime.maxActivePaths, 4);
    expect(
      configuration.asrRuntime.rule1MinTrailingSilence,
      const Duration(milliseconds: 2400),
    );
    expect(
      configuration.asrRuntime.rule2MinTrailingSilence,
      const Duration(milliseconds: 1200),
    );
    expect(
      configuration.asrRuntime.maxUtteranceDuration,
      const Duration(seconds: 15),
    );
    expect(configuration.asrRuntime.maxPendingAudioChunks, 8);
    expect(configuration.asrRuntime.debug, isFalse);
    expect(configuration.asrWakePhrase, 'assistant');
  });

  test('rejects malformed floating-point compile values', () {
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(dialogueTemperature: 'not-a-number'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(commentTopP: 'Infinity'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(contextTokens: 'not-an-integer'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(speed: 'NaN'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(
            archiveSizeBytes: 'twenty-megabytes',
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(trailingSilenceSeconds: 'eventually'),
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects unsafe runtime and sampling combinations', () {
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(
            contextTokens: '512',
            batchTokens: '1024',
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(randomSeed: '4294967296'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(dialogueMinP: '1.1'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(contextTokens: '511'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(gpuLayers: '2147483648'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(provider: 'coreml'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(speakerId: '1'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(speed: '0'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(silenceScale: '-0.1'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(noiseScaleW: '-0.1'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(lengthScale: '0'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(maxSentences: '0'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(debug: 'FALSE'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(
            archiveSizeBytes: '9223372036854775807',
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(expandedArchiveSizeBytes: '0'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(archiveSha256: 'not-a-digest'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          piper: PiperEnvironmentValues(
            archiveFilename: 'Qwen3-0.6B-Q4_K_M.gguf',
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          qwen: QwenEnvironmentValues(
            modelFilename: 'VOICE.EXTRACTING.TAR',
          ),
          piper: PiperEnvironmentValues(archiveRoot: 'voice'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(provider: 'coreml'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(sampleRate: '44100'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(featureDimension: '64'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(
            emptyTrailingSilenceSeconds: '1.0',
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(maximumUtteranceSeconds: '1.2'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(wakePhrase: 'Ассистент'),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AssistantBuildConfiguration.fromEnvironment(
        values: const AssistantEnvironmentValues(
          asr: AsrEnvironmentValues(
            archiveFilename: 'Qwen3-0.6B-Q4_K_M.gguf',
          ),
        ),
      ),
      throwsArgumentError,
    );
  });
}
