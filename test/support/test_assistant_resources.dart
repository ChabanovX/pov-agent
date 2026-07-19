import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/assistant_bloc.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

const _testManualOptions = GenerationOptions(
  maxTokens: 32,
  temperature: 0.5,
  topP: 0.9,
  topK: 10,
  minP: 0,
);
const _testShortCommentOptions = GenerationOptions(
  maxTokens: 16,
  temperature: 0.4,
  topP: 0.8,
  topK: 8,
  minP: 0,
);

/// Assistant owners used by app-shell and lifecycle tests.
final class TestAssistantResources {
  /// Creates a coherent test assistant dependency graph.
  TestAssistantResources() : modelStore = TestModelStore(), commentGenerator = TestCommentGenerator() {
    assistantBloc = AssistantBloc(
      modelStore: modelStore,
      commentGenerator: commentGenerator,
      promptBuilder: QwenPromptBuilder(
        systemPrompt: 'Test system prompt.',
        manualOptions: _testManualOptions,
        shortCommentOptions: _testShortCommentOptions,
      ),
    );
  }

  /// Deterministic verified-model lifecycle.
  final TestModelStore modelStore;

  /// Deterministic native-generation boundary.
  final TestCommentGenerator commentGenerator;

  /// Process-style presentation owner built from the test ports.
  late final AssistantBloc assistantBloc;
}

/// In-memory model store that becomes ready immediately.
final class TestModelStore implements ModelStore {
  static const _artifact = VerifiedModelArtifact(
    modelId: 'test-model',
    revision: 'test-revision',
    filePath: '/test/model.gguf',
    byteSize: 1,
    sha256: 'test-sha',
  );

  final StreamController<ModelStoreState> _states = StreamController<ModelStoreState>.broadcast(sync: true);
  ModelStoreState _current = const ModelStoreState.idle();

  /// Number of preparation requests.
  int prepareCalls = 0;

  /// Number of foreground suspensions.
  int suspendCalls = 0;

  /// Number of terminal closes.
  int closeCalls = 0;

  @override
  ModelStoreState get current => _current;

  @override
  Stream<ModelStoreState> get states => _states.stream;

  @override
  Future<AppResult<VerifiedModelArtifact>> prepare() async {
    prepareCalls += 1;
    _current = ModelStoreState.ready(_artifact);
    _states.add(_current);
    return const AppSuccess(_artifact);
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    _current = const ModelStoreState.suspended();
    _states.add(_current);
  }

  @override
  Future<void> close() async {
    if (closeCalls > 0) return;
    closeCalls += 1;
    await _states.close();
  }
}

/// Generation boundary that records lifecycle ownership in app tests.
final class TestCommentGenerator implements CommentGenerator {
  /// Number of native unload requests.
  int unloadCalls = 0;

  /// Number of terminal closes.
  int closeCalls = 0;

  /// Failures thrown by successive terminal-close attempts.
  final List<Exception> closeFailures = [];

  bool _closed = false;

  @override
  Future<AppResult<void>> loadModel(VerifiedModelArtifact artifact) async {
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<GenerationHandle>> generate(
    CommentGenerationRequest request,
  ) async {
    return const AppError(
      UnexpectedFailure(
        code: 'test_generation_not_configured',
        message: 'This app-shell fake does not generate text.',
      ),
    );
  }

  @override
  Future<void> unload() async {
    unloadCalls += 1;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    closeCalls += 1;
    if (closeFailures.isNotEmpty) throw closeFailures.removeAt(0);
    _closed = true;
  }
}
