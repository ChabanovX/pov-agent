import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_inference_worker.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_native_runtime.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

const _testGenerationOptions = GenerationOptions(
  maxTokens: 16,
  temperature: 0.4,
  topP: 0.8,
  topK: 8,
  minP: 0,
);

void main() {
  const runtimeConfiguration = LlamaRuntimeConfiguration(
    contextTokens: 2048,
    batchTokens: 512,
    threadCount: 4,
    gpuLayers: 99,
  );
  const artifact = VerifiedModelArtifact(
    modelId: 'Qwen3-0.6B-GGUF',
    revision: 'pinned-revision',
    filePath: '/models/qwen.gguf',
    byteSize: 123,
    sha256: 'abc123',
  );

  late _FakeLlamaWorker worker;
  late LlamaCommentGenerator generator;

  setUp(() {
    worker = _FakeLlamaWorker();
    generator = LlamaCommentGenerator(
      createWorker: () async => worker,
      runtimeConfiguration: runtimeConfiguration,
      randomSeed: 42,
    );
  });

  tearDown(() => generator.close());

  test('shares an equivalent model load and forwards runtime policy', () async {
    final results = await Future.wait([
      generator.loadModel(artifact),
      generator.loadModel(artifact),
    ]);

    expect(results, everyElement(isA<AppSuccess<void>>()));
    expect(worker.loadCalls, 1);
    expect(worker.loadedPath, artifact.filePath);
    expect(worker.runtimeConfiguration, same(runtimeConfiguration));
  });

  test('reports the loaded native backend until the model unloads', () async {
    worker.usesGpu = true;

    expect(generator.loadedModelUsesGpu, isNull);
    expect(generator.lastUnloadSucceeded, isNull);
    expect(await generator.loadModel(artifact), isA<AppSuccess<void>>());
    expect(generator.loadedModelUsesGpu, isTrue);

    await generator.unload();

    expect(generator.loadedModelUsesGpu, isNull);
    expect(generator.lastUnloadSucceeded, isTrue);
  });

  test('records a propagated native cleanup failure for diagnostics', () async {
    expect(await generator.loadModel(artifact), isA<AppSuccess<void>>());
    worker.unloadError = const LlamaWorkerException(
      status: -10,
      message: 'native quiescence failed',
    );

    await generator.unload();

    expect(generator.loadedModelUsesGpu, isNull);
    expect(generator.lastUnloadSucceeded, isFalse);
  });

  test('normalizes native model load failures', () async {
    worker.loadError = const LlamaWorkerException(
      status: -2,
      message: 'bad gguf',
    );

    final result = await generator.loadModel(artifact);

    expect(
      result,
      isA<AppError<void>>().having(
        (result) => result.failure,
        'failure',
        isA<DeviceUnavailableFailure>().having(
          (failure) => failure.code,
          'code',
          'assistant_model_load',
        ),
      ),
    );
    expect(generator.loadedModelUsesGpu, isNull);
  });

  test('recreates the worker after its initial spawn fails', () async {
    await generator.close();
    var spawnAttempts = 0;
    generator = LlamaCommentGenerator(
      createWorker: () async {
        spawnAttempts += 1;
        if (spawnAttempts == 1) {
          throw StateError('isolate handshake failed');
        }
        return worker;
      },
      runtimeConfiguration: runtimeConfiguration,
      randomSeed: 42,
    );

    final first = await generator.loadModel(artifact);
    final retry = await generator.loadModel(artifact);

    expect(first, isA<AppError<void>>());
    expect(retry, isA<AppSuccess<void>>());
    expect(spawnAttempts, 2);
    expect(worker.loadCalls, 1);
  });

  test(
    'retires a failed model runtime before retrying on a new worker',
    () async {
      await generator.close();
      final failedWorker = _FakeLlamaWorker()
        ..loadError = const LlamaWorkerException(
          status: -2,
          message: 'model load failed',
        );
      final recoveredWorker = _FakeLlamaWorker();
      var spawnAttempts = 0;
      generator = LlamaCommentGenerator(
        createWorker: () async {
          spawnAttempts += 1;
          return spawnAttempts == 1 ? failedWorker : recoveredWorker;
        },
        runtimeConfiguration: runtimeConfiguration,
        randomSeed: 42,
      );

      final first = await generator.loadModel(artifact);
      final retry = await generator.loadModel(artifact);

      expect(first, isA<AppError<void>>());
      expect(retry, isA<AppSuccess<void>>());
      expect(failedWorker.closeCalls, 1);
      expect(recoveredWorker.loadCalls, 1);
    },
  );

  test('persistent worker close is idempotent and terminal', () async {
    final nativeWorker = await NativeLlamaInferenceWorker.spawn();

    await Future.wait([nativeWorker.close(), nativeWorker.close()]);

    await expectLater(
      nativeWorker.load('/models/unused.gguf', runtimeConfiguration),
      throwsA(isA<StateError>()),
    );
  });

  test('concurrent generator closes join the same native teardown', () async {
    await generator.loadModel(artifact);
    final closeGate = worker.closeGate = Completer<void>();

    final first = generator.close();
    final second = generator.close();
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(worker.closeCalls, 1);

    closeGate.complete();
    await Future.wait([first, second]);
  });

  test('retries a worker close that retained native ownership', () async {
    await generator.loadModel(artifact);
    final closeFailure = Exception('native destroy failed');
    worker.closeErrors.add(closeFailure);

    await expectLater(generator.close(), throwsA(same(closeFailure)));
    expect(worker.closeCalls, 1);

    await generator.close();
    await generator.close();

    expect(worker.closeCalls, 2);
  });

  test('counts generation requests rejected by the native single-flight slot', () async {
    await generator.loadModel(artifact);
    final active = _successHandle(
      await generator.generate(
        CommentGenerationRequest(
          prompt: 'first prompt',
          options: _testGenerationOptions,
          completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
        ),
      ),
    );

    final rejected = await generator.generate(
      CommentGenerationRequest(
        prompt: 'overlapping prompt',
        options: _testGenerationOptions,
        completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
      ),
    );

    expect(
      rejected,
      isA<AppError<GenerationHandle>>().having(
        (result) => result.failure.code,
        'code',
        'assistant_generation_busy',
      ),
    );
    expect(generator.generationBusyRejections, 1);
    await active.cancel();
  });

  test(
    'decodes split UTF-8 and never publishes prompt-prefilled reasoning',
    () async {
      await generator.loadModel(artifact);
      final nativeGeneration = _FakeWorkerGeneration();
      worker.nextGeneration = nativeGeneration;
      const options = GenerationOptions(
        maxTokens: 17,
        temperature: 0.61,
        topP: 0.92,
        topK: 19,
        minP: 0.04,
      );
      final result = await generator.generate(
        CommentGenerationRequest(
          prompt: 'chatml prompt',
          options: options,
          completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
          startsInsideReasoning: true,
        ),
      );
      final handle = _successHandle(result);
      final visibleChunks = <String>[];
      final chunksDone = handle.chunks.listen(visibleChunks.add).asFuture<void>();

      nativeGeneration.addText('private chain of thought</thi');
      final answerBytes = utf8.encode('nk>\nVisible 🌹');
      nativeGeneration
        ..addBytes(answerBytes.sublist(0, answerBytes.length - 2))
        ..addBytes(answerBytes.sublist(answerBytes.length - 2));
      await nativeGeneration.finish();
      final completion = await handle.completion;
      await chunksDone;

      expect(visibleChunks.join(), 'Visible 🌹');
      expect(visibleChunks.join(), isNot(contains('private')));
      expect(completion, isA<AppSuccess<String>>());
      expect((completion as AppSuccess<String>).value, 'Visible 🌹');
      expect(worker.generatedPrompt, 'chatml prompt');
      expect(
        worker.sampling,
        isA<LlamaSamplingConfiguration>()
            .having((value) => value.maxTokens, 'maxTokens', 17)
            .having((value) => value.temperature, 'temperature', 0.61)
            .having((value) => value.topP, 'topP', 0.92)
            .having((value) => value.topK, 'topK', 19)
            .having((value) => value.minP, 'minP', 0.04)
            .having((value) => value.seed, 'seed', 42),
      );
    },
  );

  test(
    'publishes the first substantive sentence and then stops native decoding',
    () async {
      await generator.loadModel(artifact);
      final nativeGeneration = _FakeWorkerGeneration(holdCancellation: true);
      worker.nextGeneration = nativeGeneration;
      final handle = _successHandle(
        await generator.generate(
          CommentGenerationRequest(
            prompt: 'short comment prompt',
            options: _testGenerationOptions,
            completionPolicy: GenerationCompletionPolicy.firstSubstantiveEnglishSentence,
          ),
        ),
      );
      final chunks = <String>[];
      final chunksDone = handle.chunks.listen(chunks.add).asFuture<void>();

      nativeGeneration.addText(
        '<think>Maybe? private.</think>\n\n'
        'Sure! A person is visible. Extra sentence.',
      );
      await Future<void>.delayed(Duration.zero);

      expect(nativeGeneration.cancelCalls, 1);
      expect(chunks.join(), contains('A person is visible.'));
      expect(chunks.join(), isNot(contains('private')));
      var completionSettled = false;
      unawaited(handle.completion.then((_) => completionSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(completionSettled, isFalse);

      await nativeGeneration.releaseCancellation();
      final completion = await handle.completion;
      await chunksDone;

      expect(completion, isA<AppSuccess<String>>());
      expect(chunks.join(), contains('A person is visible.'));
      expect(
        (completion as AppSuccess<String>).value,
        'A person is visible.',
      );
    },
  );

  test('rejects a short comment that reaches model end mid-sentence', () async {
    await generator.loadModel(artifact);
    final nativeGeneration = _FakeWorkerGeneration();
    worker.nextGeneration = nativeGeneration;
    final handle = _successHandle(
      await generator.generate(
        CommentGenerationRequest(
          prompt: 'short comment prompt',
          options: _testGenerationOptions,
          completionPolicy: GenerationCompletionPolicy.firstSubstantiveEnglishSentence,
        ),
      ),
    );
    final chunks = <String>[];
    final chunksDone = handle.chunks.listen(chunks.add).asFuture<void>();

    nativeGeneration.addText('A person remains partially described');
    await nativeGeneration.finish();
    final completion = await handle.completion;
    await chunksDone;

    expect(chunks.join(), 'A person remains partially described');
    expect(
      completion,
      isA<AppError<String>>().having(
        (result) => result.failure.code,
        'code',
        'assistant_sentence_incomplete',
      ),
    );
  });

  test(
    'joins native completion when policy cancellation fails',
    () async {
      await generator.loadModel(artifact);
      final cancelError = Exception('native cancellation failed');
      final nativeGeneration = _FakeWorkerGeneration()..cancelError = cancelError;
      worker.nextGeneration = nativeGeneration;
      final handle = _successHandle(
        await generator.generate(
          CommentGenerationRequest(
            prompt: 'short comment prompt',
            options: _testGenerationOptions,
            completionPolicy: GenerationCompletionPolicy.firstSubstantiveEnglishSentence,
          ),
        ),
      );
      final chunks = <String>[];
      final chunksDone = handle.chunks.listen(chunks.add).asFuture<void>();

      nativeGeneration.addText('A person is visible. Extra sentence.');
      await Future<void>.delayed(Duration.zero);

      expect(nativeGeneration.cancelCalls, 1);
      var completionSettled = false;
      unawaited(handle.completion.then((_) => completionSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(completionSettled, isFalse);
      expect(chunks.join(), contains('A person is visible.'));

      await nativeGeneration.finish();
      final completion = await handle.completion;
      await chunksDone;

      expect(
        completion,
        isA<AppError<String>>()
            .having(
              (result) => result.failure.code,
              'code',
              'assistant_generation',
            )
            .having(
              (result) => result.failure.cause,
              'cause',
              same(cancelError),
            ),
      );
      expect(chunks.join(), contains('A person is visible.'));
    },
  );

  test(
    'cancels and joins native work after a local decoding failure',
    () async {
      await generator.loadModel(artifact);
      final nativeGeneration = _FakeWorkerGeneration(holdCancellation: true);
      worker.nextGeneration = nativeGeneration;
      final handle = _successHandle(
        await generator.generate(
          CommentGenerationRequest(
            prompt: 'prompt',
            options: _testGenerationOptions,
            completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
          ),
        ),
      );

      nativeGeneration.addBytes(const [0xFF]);
      await Future<void>.delayed(Duration.zero);

      expect(nativeGeneration.cancelCalls, 1);
      var completionSettled = false;
      unawaited(handle.completion.then((_) => completionSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(completionSettled, isFalse);

      await nativeGeneration.releaseCancellation();

      expect(
        await handle.completion,
        isA<AppError<String>>().having(
          (result) => result.failure.code,
          'code',
          'assistant_generation',
        ),
      );
    },
  );

  test('cancel settles only after native generation has stopped', () async {
    await generator.loadModel(artifact);
    final nativeGeneration = _FakeWorkerGeneration(holdCancellation: true);
    worker.nextGeneration = nativeGeneration;
    final handle = _successHandle(
      await generator.generate(
        CommentGenerationRequest(
          prompt: 'prompt',
          options: _testGenerationOptions,
          completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
        ),
      ),
    );
    final chunks = <String>[];
    final chunksDone = handle.chunks.listen(chunks.add).asFuture<void>();
    nativeGeneration.addText('Visible prefix');

    var cancelSettled = false;
    final cancelTask = handle.cancel().then((_) => cancelSettled = true);
    await Future<void>.delayed(Duration.zero);
    expect(nativeGeneration.cancelCalls, 1);
    expect(cancelSettled, isFalse);

    await nativeGeneration.releaseCancellation();
    await cancelTask;
    await chunksDone;
    expect(cancelSettled, isTrue);
    expect(
      (await handle.completion as AppSuccess<String>).value,
      'Visible prefix',
    );
  });

  test(
    'keeps chunk stream clean and reports generation failure once',
    () async {
      await generator.loadModel(artifact);
      final nativeGeneration = _FakeWorkerGeneration();
      worker.nextGeneration = nativeGeneration;
      final handle = _successHandle(
        await generator.generate(
          CommentGenerationRequest(
            prompt: 'prompt',
            options: _testGenerationOptions,
            completionPolicy: GenerationCompletionPolicy.modelOrTokenLimit,
          ),
        ),
      );

      final chunksExpectation = expectLater(handle.chunks, emitsDone);
      await nativeGeneration.fail(
        const LlamaWorkerException(status: -9, message: 'decode failed'),
      );

      await chunksExpectation;
      expect(
        await handle.completion,
        isA<AppError<String>>().having(
          (result) => result.failure.code,
          'code',
          'assistant_generation',
        ),
      );
    },
  );
}

GenerationHandle _successHandle(AppResult<GenerationHandle> result) {
  return switch (result) {
    AppSuccess<GenerationHandle>(:final value) => value,
    AppError<GenerationHandle>(:final failure) => throw TestFailure(
      'Expected generation success, got ${failure.code}.',
    ),
  };
}

final class _FakeLlamaWorker implements LlamaInferenceWorker {
  int loadCalls = 0;
  int closeCalls = 0;
  String? loadedPath;
  LlamaRuntimeConfiguration? runtimeConfiguration;
  Exception? loadError;
  Exception? unloadError;
  Completer<void>? closeGate;
  final List<Exception> closeErrors = [];
  _FakeWorkerGeneration? nextGeneration;
  String? generatedPrompt;
  LlamaSamplingConfiguration? sampling;
  bool usesGpu = false;

  @override
  Future<LlamaWorkerLoadResult> load(
    String modelPath,
    LlamaRuntimeConfiguration configuration,
  ) async {
    loadCalls += 1;
    loadedPath = modelPath;
    runtimeConfiguration = configuration;
    final error = loadError;
    if (error != null) throw error;
    return LlamaWorkerLoadResult(usesGpu: usesGpu);
  }

  @override
  Future<LlamaWorkerGeneration> generate(
    String prompt,
    LlamaSamplingConfiguration configuration,
  ) async {
    generatedPrompt = prompt;
    sampling = configuration;
    return nextGeneration ??= _FakeWorkerGeneration();
  }

  @override
  Future<void> unload() async {
    final error = unloadError;
    if (error != null) throw error;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (closeErrors.isNotEmpty) throw closeErrors.removeAt(0);
    await closeGate?.future;
  }
}

final class _FakeWorkerGeneration implements LlamaWorkerGeneration {
  _FakeWorkerGeneration({this.holdCancellation = false});

  final bool holdCancellation;
  final StreamController<Uint8List> _bytes = StreamController<Uint8List>();
  final Completer<void> _completion = Completer<void>();
  final Completer<void> _cancelRelease = Completer<void>();
  Exception? cancelError;
  int cancelCalls = 0;

  @override
  Stream<Uint8List> get bytes => _bytes.stream;

  @override
  Future<void> get completion => _completion.future;

  void addText(String value) => addBytes(utf8.encode(value));

  void addBytes(List<int> value) => _bytes.add(Uint8List.fromList(value));

  Future<void> finish() async {
    if (_completion.isCompleted) return;
    await _bytes.close();
    _completion.complete();
  }

  Future<void> fail(Object error) async {
    if (_completion.isCompleted) return;
    await _bytes.close();
    _completion.completeError(error);
  }

  Future<void> releaseCancellation() async {
    if (!_cancelRelease.isCompleted) _cancelRelease.complete();
    await completion;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    final error = cancelError;
    if (error != null) throw error;
    if (holdCancellation) await _cancelRelease.future;
    await finish();
  }
}
