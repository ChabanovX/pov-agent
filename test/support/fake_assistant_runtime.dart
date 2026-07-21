import 'dart:async';

import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

const testQwenArtifact = VerifiedModelArtifact(
  modelId: 'unsloth/Qwen3-0.6B-GGUF',
  revision: 'test-revision',
  filePath: '/tmp/Qwen3-0.6B-Q4_K_M.gguf',
  byteSize: 396705472,
  sha256: 'test-sha256',
);

final class FakeSceneSource implements SceneSource {
  factory FakeSceneSource({
    SceneSnapshot current = const SceneSnapshot.empty(),
  }) {
    return FakeSceneSource._(current);
  }

  FakeSceneSource._(this._current);

  final StreamController<SceneSnapshot> _changes = StreamController<SceneSnapshot>.broadcast(sync: true);
  SceneSnapshot _current;

  @override
  SceneSnapshot get current => _current;

  @override
  Stream<SceneSnapshot> get changes => _changes.stream;

  void emit(SceneSnapshot scene) {
    _current = scene;
    _changes.add(scene);
  }

  set current(SceneSnapshot scene) {
    _current = scene;
  }

  Future<void> close() => _changes.close();
}

final class FakeAssistantModelStore implements QwenModelStore {
  factory FakeAssistantModelStore({
    QwenModelStoreState current = const QwenModelStoreState.idle(),
    Future<AppResult<VerifiedModelArtifact>> Function()? onPrepare,
    Future<void> Function()? onSuspend,
  }) {
    return FakeAssistantModelStore._(current, onPrepare, onSuspend);
  }

  FakeAssistantModelStore._(
    this._current,
    this.onPrepare,
    this.onSuspend,
  );

  final StreamController<QwenModelStoreState> _states = StreamController.broadcast(
    sync: true,
  );
  QwenModelStoreState _current;

  Future<AppResult<VerifiedModelArtifact>> Function()? onPrepare;
  Future<void> Function()? onSuspend;
  int prepareCalls = 0;
  int suspendCalls = 0;
  int closeCalls = 0;

  @override
  QwenModelStoreState get current => _current;

  @override
  Stream<QwenModelStoreState> get states => _states.stream;

  void emit(QwenModelStoreState state) {
    _current = state;
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Future<AppResult<VerifiedModelArtifact>> prepare() async {
    prepareCalls += 1;
    final callback = onPrepare;
    if (callback != null) return callback();
    emit(QwenModelStoreState.ready(testQwenArtifact));
    return const AppSuccess(testQwenArtifact);
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    await onSuspend?.call();
    emit(const QwenModelStoreState.suspended());
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await _states.close();
  }
}

final class FakeCommentGenerator implements CommentGenerator {
  final List<CommentGenerationRequest> requests = [];
  final List<AppResult<GenerationHandle>> _queuedResults = [];

  Future<AppResult<GenerationHandle>> Function(CommentGenerationRequest)? onGenerate;
  int loadCalls = 0;
  int unloadCalls = 0;
  int closeCalls = 0;

  void enqueueHandle(FakeGenerationHandle handle) {
    _queuedResults.add(AppSuccess<GenerationHandle>(handle));
  }

  void enqueueFailure(AppFailure failure) {
    _queuedResults.add(AppError<GenerationHandle>(failure));
  }

  @override
  Future<AppResult<void>> loadModel(VerifiedModelArtifact artifact) async {
    loadCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<GenerationHandle>> generate(
    CommentGenerationRequest request,
  ) async {
    requests.add(request);
    final callback = onGenerate;
    if (callback != null) return callback(request);
    if (_queuedResults.isEmpty) {
      return const AppError(
        UnexpectedFailure(code: 'fake_generation_not_configured'),
      );
    }
    return _queuedResults.removeAt(0);
  }

  @override
  Future<void> unload() async {
    unloadCalls += 1;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

final class FakeSpeechSynthesizer implements SpeechSynthesizer {
  final List<String> spokenTexts = [];
  final List<FakeSpeechAttempt> _queuedAttempts = [];

  Future<AppResult<void>> Function()? onStop;
  FakeSpeechAttempt? _active;
  int stopCalls = 0;
  int closeCalls = 0;
  bool _closed = false;

  void enqueueAttempt(FakeSpeechAttempt attempt) {
    _queuedAttempts.add(attempt);
  }

  @override
  Future<AppResult<void>> speak(String text) {
    spokenTexts.add(text);
    if (_closed) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'fake_speech_closed'),
        ),
      );
    }
    if (_active != null) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'fake_speech_busy'),
        ),
      );
    }
    if (_queuedAttempts.isEmpty) {
      return Future.value(const AppSuccess<void>(null));
    }

    final attempt = _queuedAttempts.removeAt(0);
    _active = attempt;
    return attempt.completion.whenComplete(() {
      if (identical(_active, attempt)) _active = null;
    });
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls += 1;
    final result = await onStop?.call() ?? const AppSuccess<void>(null);
    if (result is AppSuccess<void>) _active?.succeed();
    return result;
  }

  @override
  Future<AppResult<void>> close() async {
    closeCalls += 1;
    final result = await stop();
    if (result is AppSuccess<void>) _closed = true;
    return result;
  }
}

final class FakeSpeechAttempt {
  final Completer<AppResult<void>> _completion = Completer<AppResult<void>>();

  Future<AppResult<void>> get completion => _completion.future;

  void succeed() {
    if (!_completion.isCompleted) {
      _completion.complete(const AppSuccess<void>(null));
    }
  }

  void fail(AppFailure failure) {
    if (!_completion.isCompleted) _completion.complete(AppError<void>(failure));
  }
}

final class FakeGenerationHandle implements GenerationHandle {
  FakeGenerationHandle({bool syncChunks = false}) : _chunks = StreamController<String>(sync: syncChunks);

  final StreamController<String> _chunks;
  final Completer<AppResult<String>> _completion = Completer();
  final StringBuffer _visibleAnswer = StringBuffer();
  Future<void>? _cancelTask;

  int cancelCalls = 0;
  Future<void> Function()? onCancel;

  bool get chunksClosed => _chunks.isClosed;

  @override
  Stream<String> get chunks => _chunks.stream;

  @override
  Future<AppResult<String>> get completion => _completion.future;

  void emit(String chunk) {
    _visibleAnswer.write(chunk);
    _chunks.add(chunk);
  }

  void succeed([String? answer]) {
    if (_completion.isCompleted) return;
    unawaited(_chunks.close());
    _completion.complete(AppSuccess(answer ?? _visibleAnswer.toString()));
  }

  void fail(AppFailure failure) {
    if (_completion.isCompleted) return;
    unawaited(_chunks.close());
    _completion.complete(AppError(failure));
  }

  @override
  Future<void> cancel() {
    return _cancelTask ??= _cancelOnce();
  }

  Future<void> _cancelOnce() async {
    cancelCalls += 1;
    await onCancel?.call();
    if (_completion.isCompleted) return;
    unawaited(_chunks.close());
    _completion.complete(AppSuccess(_visibleAnswer.toString()));
  }
}
