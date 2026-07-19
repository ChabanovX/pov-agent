import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';

const _testGenerationOptions = GenerationOptions(
  maxTokens: 8,
  temperature: 0.5,
  topP: 0.7,
  topK: 4,
  minP: 0.1,
);

void main() {
  const artifact = VerifiedModelArtifact(
    modelId: 'qwen3-0.6b',
    revision: 'pinned-revision',
    filePath: '/models/qwen.gguf',
    byteSize: 416000000,
    sha256: 'verified-digest',
  );

  test('includes min-p in validated value equality', () {
    const first = GenerationOptions(
      maxTokens: 8,
      temperature: 0.5,
      topP: 0.7,
      topK: 4,
      minP: 0.1,
    );
    const same = GenerationOptions(
      maxTokens: 8,
      temperature: 0.5,
      topP: 0.7,
      topK: 4,
      minP: 0.1,
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(
      () => GenerationOptions(
        maxTokens: 8,
        temperature: 0.5,
        topP: 0.7,
        topK: 4,
        minP: -0.1,
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => GenerationOptions(
        maxTokens: 8,
        temperature: 0.5,
        topP: 0.7,
        topK: 4,
        minP: 1.1,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('represents model preparation without ambiguous nullable fields', () {
    const downloading = ModelStoreState.downloading(0.4);
    final ready = ModelStoreState.ready(artifact);
    const failure = CacheFailure(code: 'model_checksum');
    final failed = ModelStoreState.failure(failure);

    expect(downloading.phase, ModelStorePhase.downloading);
    expect(downloading.downloadProgress, 0.4);
    expect(downloading.artifact, isNull);
    expect(ready.phase, ModelStorePhase.ready);
    expect(ready.artifact, artifact);
    expect(ready.downloadProgress, isNull);
    expect(failed.phase, ModelStorePhase.failure);
    expect(failed.failure, same(failure));
  });

  test('requires a non-empty formatted generation prompt', () {
    expect(
      () => CommentGenerationRequest(
        prompt: ' \n ',
        options: _testGenerationOptions,
      ),
      throwsArgumentError,
    );

    final request = CommentGenerationRequest(
      prompt: '<|im_start|>assistant\n',
      options: _testGenerationOptions,
    );
    expect(request.options, _testGenerationOptions);
  });
}
