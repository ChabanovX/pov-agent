import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/app/model_pack/model_pack_receipt_store.dart';
import 'package:pov_agent/app/model_pack/model_pack_state.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/camera/application/models/verified_vision_model_artifact.dart';
import 'package:pov_agent/features/camera/application/ports/vision_model_verifier.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  const sufficientCapacity = ModelPackState.requiredStorageBytes + 1;
  const fingerprint = 'pack-v1';
  const qwenArtifact = VerifiedModelArtifact(
    modelId: 'test/qwen',
    revision: 'qwen-revision',
    filePath: '/models/qwen.gguf',
    byteSize: 1,
    sha256: 'qwen-digest',
  );
  const piperArtifact = VerifiedPiperModelBundle(
    modelId: 'test/piper',
    revision: 'piper-revision',
    bundleDirectoryPath: '/models/piper',
    modelFilePath: '/models/piper/voice.onnx',
    tokensFilePath: '/models/piper/tokens.txt',
    espeakDataDirectoryPath: '/models/piper/espeak-ng-data',
    extractedByteSize: 1,
    extractedFileCount: 1,
    bundleTreeSha256: 'piper-digest',
  );
  const asrArtifact = VerifiedAsrModelBundle(
    modelId: 'test/asr',
    revision: 'asr-revision',
    bundleDirectoryPath: '/models/asr',
    modelFilePath: '/models/asr/model.onnx',
    tokensFilePath: '/models/asr/tokens.txt',
    extractedByteSize: 1,
    extractedFileCount: 1,
    bundleTreeSha256: 'asr-digest',
  );
  const visionArtifact = VerifiedVisionModelArtifact(
    modelId: 'test/yolo',
    revision: 'vision-revision',
    assetPath: 'assets/models/yolo.tflite',
    byteSize: 1,
    sha256: 'vision-digest',
  );

  late List<String> preparationOrder;
  late _FakeModelStore<VerifiedModelArtifact> qwenStore;
  late _FakeVisionModelVerifier visionVerifier;
  late _FakeModelStore<VerifiedPiperModelBundle> piperStore;
  late _FakeModelStore<VerifiedAsrModelBundle> asrStore;
  late _FakeReceiptStore receiptStore;
  ModelPackController? controller;

  ModelPackController createController({
    ModelPackCapacityReader? capacityReader,
    String modelPackFingerprint = fingerprint,
  }) {
    return controller = ModelPackController(
      qwenStore: qwenStore,
      visionVerifier: visionVerifier,
      piperStore: piperStore,
      asrStore: asrStore,
      receiptStore: receiptStore,
      capacityReader: capacityReader ?? () async => sufficientCapacity,
      fingerprint: modelPackFingerprint,
      qwenDownloadBytes: 100,
      piperDownloadBytes: 200,
      asrDownloadBytes: 300,
    );
  }

  setUp(() {
    preparationOrder = [];
    qwenStore = _FakeModelStore(
      name: 'qwen',
      artifact: qwenArtifact,
      preparationOrder: preparationOrder,
    );
    visionVerifier = _FakeVisionModelVerifier(
      artifact: visionArtifact,
      preparationOrder: preparationOrder,
    );
    piperStore = _FakeModelStore(
      name: 'piper',
      artifact: piperArtifact,
      preparationOrder: preparationOrder,
    );
    asrStore = _FakeModelStore(
      name: 'asr',
      artifact: asrArtifact,
      preparationOrder: preparationOrder,
    );
    receiptStore = _FakeReceiptStore();
    controller = null;
  });

  tearDown(() async {
    await controller?.close();
    await qwenStore.close();
    await piperStore.close();
    await asrStore.close();
  });

  test('preflight without a receipt waits for explicit installation', () async {
    final target = createController();
    final published = <ModelPackState>[];
    final subscription = target.states.listen(published.add);

    await target.start();

    expect(target.current.phase, ModelPackPhase.ready);
    expect(target.current.availableStorageBytes, sufficientCapacity);
    expect(receiptStore.readCalls, 1);
    expect(preparationOrder, isEmpty);
    expect(receiptStore.writes, isEmpty);
    expect(
      published.map((state) => state.phase),
      [ModelPackPhase.checking, ModelPackPhase.ready],
    );
    await subscription.cancel();
  });

  test('insufficient storage blocks install and can be checked again', () async {
    final capacities = <int>[
      ModelPackState.requiredStorageBytes - 1,
      sufficientCapacity,
    ];
    final target = createController(
      capacityReader: () async => capacities.removeAt(0),
    );

    await target.start();

    expect(target.current.phase, ModelPackPhase.failure);
    expect(target.current.availableStorageBytes, lessThan(sufficientCapacity));
    expect(target.current.failure?.code, 'model_pack_insufficient_storage');
    await target.install();
    expect(preparationOrder, isEmpty);

    await target.checkAgain();

    expect(target.current.phase, ModelPackPhase.ready);
    expect(target.current.availableStorageBytes, sufficientCapacity);
    expect(receiptStore.readCalls, 2);
  });

  test('matching receipt verifies every cache before storage policy', () async {
    receiptStore.value = fingerprint;
    var capacityCalls = 0;
    final target = createController(
      capacityReader: () async {
        capacityCalls += 1;
        return 0;
      },
    );

    await target.start();

    expect(preparationOrder, ['qwen', 'vision', 'piper', 'asr']);
    expect(capacityCalls, 0);
    expect(target.current.phase, ModelPackPhase.complete);
    expect(
      target.current.items.map((item) => item.phase),
      everyElement(ModelPackItemPhase.verified),
    );
    expect(receiptStore.writes, isEmpty);
  });

  test('incomplete receipt cache verifies all rows before first-install headroom', () async {
    receiptStore.value = fingerprint;
    piperStore.cachePresent = false;
    final target = createController(
      capacityReader: () async => ModelPackState.requiredStorageBytes - 1,
    );

    await target.start();

    expect(preparationOrder, ['qwen', 'vision', 'piper', 'asr']);
    expect(qwenStore.prepareCalls, 0);
    expect(piperStore.prepareCalls, 0);
    expect(asrStore.prepareCalls, 0);
    expect(receiptStore.clearCalls, 1);
    expect(target.current.phase, ModelPackPhase.failure);
    expect(target.current.failure?.code, 'model_pack_insufficient_storage');
    expect(
      target.current.item(ModelPackItemKind.voice).phase,
      ModelPackItemPhase.waiting,
    );
  });

  test('retry keeps verified work and resumes at the failed store', () async {
    const failure = NetworkFailure(code: 'piper_download_failed');
    piperStore.behaviors.addAll([
      (store) async {
        store.publish(ModelStoreState.failure(failure));
        return const AppError(failure);
      },
      (store) => store.succeed(),
    ]);
    final target = createController();
    await target.start();

    await target.install();

    expect(target.current.phase, ModelPackPhase.failure);
    expect(target.current.failure, same(failure));
    expect(target.current.item(ModelPackItemKind.assistant).phase, ModelPackItemPhase.verified);
    expect(target.current.item(ModelPackItemKind.voice).phase, ModelPackItemPhase.failure);
    expect(preparationOrder, ['qwen', 'vision', 'piper']);
    expect(receiptStore.writes, isEmpty);

    await target.install();

    expect(preparationOrder, ['qwen', 'vision', 'piper', 'piper', 'asr']);
    expect(qwenStore.prepareCalls, 1);
    expect(target.current.phase, ModelPackPhase.complete);
    expect(receiptStore.writes, [fingerprint]);
  });

  test('unexpected store exceptions become setup failures', () async {
    qwenStore.behaviors.add(
      (_) => Future<AppResult<VerifiedModelArtifact>>.error(
        StateError('artifact preparation crashed'),
      ),
    );
    final target = createController();
    await target.start();

    await target.install();

    expect(target.current.phase, ModelPackPhase.failure);
    expect(
      target.current.failure,
      isA<UnexpectedFailure>().having(
        (failure) => failure.code,
        'code',
        'model_pack_assistant_prepare_failed',
      ),
    );
    expect(piperStore.prepareCalls, 0);
    expect(asrStore.prepareCalls, 0);
  });

  test('cancellation is shared and stale preparation cannot resume setup', () async {
    final preparation = Completer<AppResult<VerifiedModelArtifact>>();
    final suspendGate = Completer<void>();
    qwenStore
      ..behaviors.add((store) {
        store.publish(const ModelStoreState.downloading(0.25));
        return preparation.future;
      })
      ..suspendGate = suspendGate;
    final target = createController();
    await target.start();
    final installation = target.install();
    await Future<void>.delayed(Duration.zero);

    final firstCancellation = target.cancel();
    final secondCancellation = target.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(identical(firstCancellation, secondCancellation), isTrue);
    expect(target.current.phase, ModelPackPhase.cancelling);
    expect(qwenStore.suspendCalls, 1);
    expect(piperStore.suspendCalls, 1);
    expect(asrStore.suspendCalls, 1);

    suspendGate.complete();
    await firstCancellation;
    expect(target.current.phase, ModelPackPhase.ready);
    expect(target.current.item(ModelPackItemKind.assistant).phase, ModelPackItemPhase.waiting);

    preparation.complete(const AppSuccess(qwenArtifact));
    await installation;

    expect(target.current.phase, ModelPackPhase.ready);
    expect(piperStore.prepareCalls, 0);
    expect(asrStore.prepareCalls, 0);
    expect(receiptStore.writes, isEmpty);
  });

  test('synchronous state listeners can cancel the operation they observe', () async {
    final target = createController();
    await target.start();
    Future<void>? cancellation;
    final subscription = target.states.listen((state) {
      if (state.phase == ModelPackPhase.installing && cancellation == null) {
        cancellation = target.cancel();
      }
    });

    await target.install();
    await cancellation;

    expect(cancellation, isNotNull);
    expect(target.current.phase, ModelPackPhase.ready);
    expect(preparationOrder, isEmpty);
    await subscription.cancel();
  });

  test('suspend exceptions leave cancellation in a recoverable failure', () async {
    final preparation = Completer<AppResult<VerifiedModelArtifact>>();
    qwenStore
      ..behaviors.add((_) => preparation.future)
      ..suspendError = StateError('suspend failed');
    final target = createController();
    await target.start();
    final installation = target.install();
    await Future<void>.delayed(Duration.zero);

    await target.cancel();

    expect(target.current.phase, ModelPackPhase.failure);
    expect(target.current.failure?.code, 'model_pack_cancel_failed');
    expect(piperStore.suspendCalls, 1);
    expect(asrStore.suspendCalls, 1);

    preparation.complete(const AppSuccess(qwenArtifact));
    await installation;
  });

  test('receipt write failure retries without preparing verified stores again', () async {
    receiptStore.writeError = StateError('read-only volume');
    final target = createController();
    await target.start();

    await target.install();

    expect(target.current.phase, ModelPackPhase.failure);
    expect(target.current.failure?.code, 'model_pack_receipt_write_failed');
    expect(preparationOrder, ['qwen', 'vision', 'piper', 'asr']);

    receiptStore.writeError = null;
    await target.install();

    expect(preparationOrder, ['qwen', 'vision', 'piper', 'asr']);
    expect(target.current.phase, ModelPackPhase.complete);
    expect(receiptStore.writes, [fingerprint]);
  });

  test('capacity and receipt read exceptions are normalized', () async {
    final storageTarget = createController(
      capacityReader: () => Future<int>.error(StateError('capacity failed')),
    );

    await storageTarget.start();

    expect(storageTarget.current.failure?.code, 'model_pack_storage_unavailable');
    expect(storageTarget.current.availableStorageBytes, isNull);

    await storageTarget.close();
    receiptStore.readError = StateError('receipt failed');
    final receiptTarget = createController();

    await receiptTarget.start();

    expect(receiptTarget.current.failure?.code, 'model_pack_receipt_read_failed');
    expect(receiptTarget.current.availableStorageBytes, isNull);
    expect(preparationOrder, isEmpty);
  });

  test('close invalidates work that has been scheduled but not started', () async {
    var capacityCalls = 0;
    final target = createController(
      capacityReader: () async {
        capacityCalls += 1;
        return sufficientCapacity;
      },
    );

    final check = target.start();
    await target.close();
    await check;

    expect(capacityCalls, 0);
    expect(preparationOrder, isEmpty);
  });
}

typedef _PrepareBehavior<TArtifact extends Object> =
    Future<AppResult<TArtifact>> Function(_FakeModelStore<TArtifact> store);

final class _FakeModelStore<TArtifact extends Object> implements CacheVerifyingModelStore<TArtifact> {
  _FakeModelStore({
    required this.name,
    required this.artifact,
    required this.preparationOrder,
  });

  final String name;
  final TArtifact artifact;
  final List<String> preparationOrder;
  final List<_PrepareBehavior<TArtifact>> behaviors = [];
  final StreamController<ModelStoreState<TArtifact>> _states = StreamController.broadcast(sync: true);

  @override
  ModelStoreState<TArtifact> current = const ModelStoreState.idle();
  Completer<void>? suspendGate;
  Error? suspendError;
  int prepareCalls = 0;
  int verifyCacheCalls = 0;
  int suspendCalls = 0;
  bool cachePresent = true;
  var _closed = false;

  @override
  Stream<ModelStoreState<TArtifact>> get states => _states.stream;

  @override
  Future<AppResult<TArtifact>> prepare() {
    prepareCalls += 1;
    preparationOrder.add(name);
    if (behaviors.isNotEmpty) return behaviors.removeAt(0)(this);
    return succeed();
  }

  @override
  Future<AppResult<bool>> verifyCache() async {
    verifyCacheCalls += 1;
    preparationOrder.add(name);
    if (!cachePresent) {
      publish(const ModelStoreState.idle());
      return const AppSuccess(false);
    }
    publish(const ModelStoreState.verifying());
    publish(ModelStoreState.ready(artifact));
    return const AppSuccess(true);
  }

  Future<AppResult<TArtifact>> succeed() async {
    publish(const ModelStoreState.loading());
    publish(ModelStoreState.ready(artifact));
    return AppSuccess(artifact);
  }

  void publish(ModelStoreState<TArtifact> state) {
    current = state;
    if (!_closed) _states.add(state);
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    final error = suspendError;
    if (error != null) throw error;
    await suspendGate?.future;
    publish(const ModelStoreState.suspended());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _states.close();
  }
}

final class _FakeVisionModelVerifier implements VisionModelVerifier {
  const _FakeVisionModelVerifier({
    required this.artifact,
    required this.preparationOrder,
  });

  final VerifiedVisionModelArtifact artifact;
  final List<String> preparationOrder;

  @override
  Future<AppResult<VerifiedVisionModelArtifact>> verify() async {
    preparationOrder.add('vision');
    return AppSuccess(artifact);
  }
}

final class _FakeReceiptStore implements ModelPackReceiptStore {
  String? value;
  Error? readError;
  Error? writeError;
  int readCalls = 0;
  int clearCalls = 0;
  final List<String> writes = [];

  @override
  Future<String?> read() async {
    readCalls += 1;
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<void> write(String fingerprint) async {
    final error = writeError;
    if (error != null) throw error;
    value = fingerprint;
    writes.add(fingerprint);
  }

  @override
  Future<void> clear() async {
    clearCalls += 1;
    value = null;
  }
}
