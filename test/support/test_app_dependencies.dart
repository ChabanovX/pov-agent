import 'dart:async';

import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/app/model_pack/model_pack_receipt_store.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

import 'fake_camera_controller.dart';
import 'test_assistant_resources.dart';

/// Process-style dependency graph used by root-router widget tests.
final class TestAppRuntime {
  TestAppRuntime({
    required this.runtime,
    required this.modelPackController,
    required this.cameraController,
    required this.assistant,
  });

  final AppRuntime runtime;
  final ModelPackController modelPackController;
  final FakeCameraController cameraController;
  final TestAssistantResources assistant;

  /// Completes the mandatory setup gate without starting [runtime].
  Future<void> completeModelPack() async {
    await modelPackController.start();
    await modelPackController.install();
  }
}

/// Builds an idle runtime and its mandatory model-pack owner.
Future<TestAppRuntime> createTestAppRuntime(
  FakeCameraController controller, {
  bool modelPackComplete = false,
}) async {
  final sceneSession = ObservationSceneSession(
    controller: controller,
    stabilizer: SceneStabilizer(),
  );
  final assistant = TestAssistantResources(sceneSource: sceneSession);
  final piperModelStore = _TestPiperModelStore();
  final modelPackController = ModelPackController(
    qwenStore: assistant.modelStore,
    visionVerifier: TestVisionModelVerifier(),
    piperStore: piperModelStore,
    asrStore: assistant.asrModelStore,
    receiptStore: _MemoryModelPackReceiptStore(),
    capacityReader: () async => ModelPackState.requiredStorageBytes + 1,
    fingerprint: 'test-model-pack-v1',
    qwenDownloadBytes: 1,
    piperDownloadBytes: 1,
    asrDownloadBytes: 1,
  );
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(
      controller,
      initiallyRequestedEnabled: false,
    ),
    sceneSession: sceneSession,
    observerBloc: assistant.observerBloc,
    modelStore: assistant.modelStore,
    asrModelStore: assistant.asrModelStore,
    commentGenerator: assistant.commentGenerator,
    speechRecognizer: assistant.speechRecognizer,
    speechSynthesizer: assistant.speechSynthesizer,
    modelPackController: modelPackController,
    standalonePiperModelStore: piperModelStore,
  );
  final dependencies = TestAppRuntime(
    runtime: runtime,
    modelPackController: modelPackController,
    cameraController: controller,
    assistant: assistant,
  );
  if (modelPackComplete) await dependencies.completeModelPack();
  return dependencies;
}

Future<void> disposeTestAppRuntime(TestAppRuntime dependencies) {
  return dependencies.runtime.close();
}

final class _MemoryModelPackReceiptStore implements ModelPackReceiptStore {
  String? _fingerprint;

  @override
  Future<void> clear() async => _fingerprint = null;

  @override
  Future<String?> read() async => _fingerprint;

  @override
  Future<void> write(String fingerprint) async {
    _fingerprint = fingerprint;
  }
}

final class _TestPiperModelStore implements CacheVerifyingModelStore<VerifiedPiperModelBundle> {
  static const _bundle = VerifiedPiperModelBundle(
    modelId: 'test-piper',
    revision: 'test-revision',
    bundleDirectoryPath: '/test/piper',
    modelFilePath: '/test/piper/voice.onnx',
    tokensFilePath: '/test/piper/tokens.txt',
    espeakDataDirectoryPath: '/test/piper/espeak-ng-data',
    extractedByteSize: 1,
    extractedFileCount: 1,
    bundleTreeSha256: 'test-tree',
  );

  final StreamController<ModelStoreState<VerifiedPiperModelBundle>> _states = StreamController.broadcast(sync: true);
  ModelStoreState<VerifiedPiperModelBundle> _current = const ModelStoreState.idle();
  var _closed = false;

  @override
  ModelStoreState<VerifiedPiperModelBundle> get current => _current;

  @override
  Stream<ModelStoreState<VerifiedPiperModelBundle>> get states => _states.stream;

  @override
  Future<AppResult<VerifiedPiperModelBundle>> prepare() async {
    _current = ModelStoreState.ready(_bundle);
    _states.add(_current);
    return const AppSuccess(_bundle);
  }

  @override
  Future<AppResult<bool>> verifyCache() async {
    _current = ModelStoreState.ready(_bundle);
    _states.add(_current);
    return const AppSuccess(true);
  }

  @override
  Future<void> suspend() async {
    _current = const ModelStoreState.suspended();
    if (!_closed) _states.add(_current);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _states.close();
  }
}
