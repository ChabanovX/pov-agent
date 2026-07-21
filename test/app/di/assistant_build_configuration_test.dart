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
  });
}
