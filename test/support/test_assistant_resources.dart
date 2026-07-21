import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/speech_recognition_event.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

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
  TestAssistantResources({SceneSource? sceneSource})
    : modelStore = TestModelStore(),
      asrModelStore = TestAsrModelStore(),
      commentGenerator = TestCommentGenerator(),
      microphonePermissionGateway = TestMicrophonePermissionGateway(),
      speechRecognizer = TestSpeechRecognizer(),
      speechSynthesizer = TestSpeechSynthesizer() {
    observerBloc = ObserverBloc(
      generation: ObserverGenerationDependencies(
        sceneSource: sceneSource ?? const _EmptySceneSource(),
        qwenModelStore: modelStore,
        commentGenerator: commentGenerator,
        requestBuilder: ObserverRequestBuilder(
          qwenPromptBuilder: QwenPromptBuilder(
            systemPrompt: 'Test system prompt.',
            dialogueOptions: _testManualOptions,
            shortCommentOptions: _testShortCommentOptions,
          ),
        ),
      ),
      voice: ObserverVoiceDependencies(
        asrModelStore: asrModelStore,
        microphonePermissionGateway: microphonePermissionGateway,
        speechRecognizer: speechRecognizer,
        speechSynthesizer: speechSynthesizer,
        wakePhrase: 'assistant',
        questionDeadline: const Duration(seconds: 15),
      ),
    );
  }

  /// Deterministic verified-model lifecycle.
  final TestModelStore modelStore;

  /// Deterministic verified streaming-ASR bundle lifecycle.
  final TestAsrModelStore asrModelStore;

  /// Deterministic native-generation boundary.
  final TestCommentGenerator commentGenerator;

  /// Deterministic microphone permission boundary.
  final TestMicrophonePermissionGateway microphonePermissionGateway;

  /// Deterministic streaming speech-recognition boundary.
  final TestSpeechRecognizer speechRecognizer;

  /// Deterministic foreground speech boundary.
  final TestSpeechSynthesizer speechSynthesizer;

  /// Process-style presentation owner built from the test ports.
  late final ObserverBloc observerBloc;
}

final class _EmptySceneSource implements SceneSource {
  const _EmptySceneSource();

  @override
  SceneSnapshot get current => const SceneSnapshot.empty();

  @override
  Stream<SceneSnapshot> get changes => const Stream.empty();
}

/// In-memory model store that becomes ready immediately.
final class TestModelStore implements QwenModelStore {
  static const _artifact = VerifiedModelArtifact(
    modelId: 'test-model',
    revision: 'test-revision',
    filePath: '/test/model.gguf',
    byteSize: 1,
    sha256: 'test-sha',
  );

  final StreamController<QwenModelStoreState> _states = StreamController<QwenModelStoreState>.broadcast(sync: true);
  QwenModelStoreState _current = const QwenModelStoreState.idle();

  /// Number of preparation requests.
  int prepareCalls = 0;

  /// Number of foreground suspensions.
  int suspendCalls = 0;

  /// Number of terminal closes.
  int closeCalls = 0;

  @override
  QwenModelStoreState get current => _current;

  @override
  Stream<QwenModelStoreState> get states => _states.stream;

  @override
  Future<AppResult<VerifiedModelArtifact>> prepare() async {
    prepareCalls += 1;
    _current = QwenModelStoreState.ready(_artifact);
    _states.add(_current);
    return const AppSuccess(_artifact);
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    _current = const QwenModelStoreState.suspended();
    _states.add(_current);
  }

  @override
  Future<void> close() async {
    if (closeCalls > 0) return;
    closeCalls += 1;
    await _states.close();
  }
}

/// In-memory ASR bundle store that becomes ready immediately.
final class TestAsrModelStore implements AsrModelStore {
  static const _bundle = VerifiedAsrModelBundle(
    modelId: 'test-asr',
    revision: 'test-revision',
    bundleDirectoryPath: '/test/asr',
    modelFilePath: '/test/asr/model.int8.onnx',
    tokensFilePath: '/test/asr/tokens.txt',
    extractedByteSize: 2,
    extractedFileCount: 2,
    bundleTreeSha256: 'test-tree',
  );

  final StreamController<ModelStoreState<VerifiedAsrModelBundle>> _states = StreamController.broadcast(sync: true);
  ModelStoreState<VerifiedAsrModelBundle> _current = const ModelStoreState.idle();

  /// Number of preparation requests.
  int prepareCalls = 0;

  /// Number of foreground suspensions.
  int suspendCalls = 0;

  /// Number of terminal closes.
  int closeCalls = 0;

  /// Failures thrown by successive terminal-close attempts.
  final List<Exception> closeFailures = [];

  bool _closed = false;

  @override
  ModelStoreState<VerifiedAsrModelBundle> get current => _current;

  @override
  Stream<ModelStoreState<VerifiedAsrModelBundle>> get states => _states.stream;

  @override
  Future<AppResult<VerifiedAsrModelBundle>> prepare() async {
    prepareCalls += 1;
    _current = ModelStoreState.ready(_bundle);
    _states.add(_current);
    return const AppSuccess(_bundle);
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    _current = const ModelStoreState.suspended();
    _states.add(_current);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    closeCalls += 1;
    if (closeFailures.isNotEmpty) throw closeFailures.removeAt(0);
    await _states.close();
    _closed = true;
  }
}

/// Permission boundary that always grants microphone access.
final class TestMicrophonePermissionGateway implements MicrophonePermissionGateway {
  /// Number of permission requests.
  int requestCalls = 0;

  @override
  Future<AppResult<void>> request() async {
    requestCalls += 1;
    return const AppSuccess<void>(null);
  }
}

/// Recognition boundary that exposes lifecycle counters without transcripts.
final class TestSpeechRecognizer implements SpeechRecognizer {
  _TestSpeechRecognitionHandle? _active;

  /// Number of native model loads.
  int loadCalls = 0;

  /// Number of microphone session starts.
  int startCalls = 0;

  /// Number of native model unloads.
  int unloadCalls = 0;

  /// Number of terminal closes.
  int closeCalls = 0;

  /// Failures returned by successive terminal-close attempts.
  final List<AppFailure> closeFailures = [];

  /// Stop count of the currently retained recognition handle.
  int get activeHandleStopCalls => _active?.stopCalls ?? 0;

  bool _closed = false;

  @override
  Future<AppResult<void>> loadModel(VerifiedAsrModelBundle bundle) async {
    loadCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<SpeechRecognitionHandle>> start() async {
    startCalls += 1;
    final handle = _TestSpeechRecognitionHandle();
    _active = handle;
    return AppSuccess<SpeechRecognitionHandle>(handle);
  }

  @override
  Future<AppResult<void>> unload() async {
    unloadCalls += 1;
    final result = await _active?.stop() ?? const AppSuccess<void>(null);
    if (result is AppSuccess<void>) _active = null;
    return result;
  }

  @override
  Future<AppResult<void>> close() async {
    if (_closed) return const AppSuccess<void>(null);
    closeCalls += 1;
    if (closeFailures.isNotEmpty) {
      return AppError<void>(closeFailures.removeAt(0));
    }
    final result = await unload();
    if (result is AppSuccess<void>) _closed = true;
    return result;
  }
}

final class _TestSpeechRecognitionHandle implements SpeechRecognitionHandle {
  final StreamController<SpeechRecognitionEvent> _events = StreamController.broadcast();
  Future<AppResult<void>>? _stopTask;

  int stopCalls = 0;

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<AppResult<void>> resetForNextSegment() async {
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> stop() => _stopTask ??= _stopOnce();

  Future<AppResult<void>> _stopOnce() async {
    stopCalls += 1;
    await _events.close();
    return const AppSuccess<void>(null);
  }
}

/// Generation boundary that records lifecycle ownership in app tests.
final class TestCommentGenerator implements CommentGenerator {
  /// Optional generation behavior for orchestration tests.
  Future<AppResult<GenerationHandle>> Function(CommentGenerationRequest request)? onGenerate;

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
    final callback = onGenerate;
    if (callback != null) return callback(request);
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

/// Speech boundary that records process ownership in app tests.
final class TestSpeechSynthesizer implements SpeechSynthesizer {
  /// Number of completed-comment speech requests.
  int speakCalls = 0;

  /// Number of cooperative stop requests.
  int stopCalls = 0;

  /// Number of terminal closes.
  int closeCalls = 0;

  /// Failures returned by successive terminal-close attempts.
  final List<AppFailure> closeFailures = [];

  bool _closed = false;

  @override
  Future<AppResult<void>> speak(String text) async {
    speakCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> close() async {
    if (_closed) return const AppSuccess<void>(null);
    closeCalls += 1;
    if (closeFailures.isNotEmpty) {
      return AppError<void>(closeFailures.removeAt(0));
    }
    _closed = true;
    return const AppSuccess<void>(null);
  }
}
