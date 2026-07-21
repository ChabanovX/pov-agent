import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/comment_generation_request.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/generation_handle.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/models/qwen_model_manifest.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_qwen_model_store.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  const reserveBytes = 32;
  final payload = Uint8List.fromList(
    List<int>.generate(128, (index) => (index * 17) % 256),
  );

  late Directory sandbox;
  late Directory modelDirectory;
  late _LoopbackArtifactServer server;
  late _FakeDiskCapacityGateway diskCapacity;
  late _FakeCommentGenerator generator;
  late VerifiedQwenModelStore store;
  late StreamSubscription<QwenModelStoreState> stateSubscription;
  late List<QwenModelStoreState> publishedStates;

  QwenModelManifest manifest({String? digest}) {
    return QwenModelManifest(
      modelId: 'test/qwen-model',
      downloadUrl: server.uri.toString(),
      revision: 'test-revision',
      filename: 'tiny-qwen.gguf',
      byteSize: payload.length,
      sha256: digest ?? sha256.convert(payload).toString(),
      license: 'Apache-2.0',
      downloadReserveBytes: reserveBytes,
    );
  }

  VerifiedQwenModelStore createStore({
    QwenModelManifest? artifactManifest,
    ModelDiskCapacityGateway? capacityGateway,
    _FakeCommentGenerator? commentGenerator,
    ModelArtifactDownloader? downloader,
  }) {
    return VerifiedQwenModelStore(
      manifest: artifactManifest ?? manifest(),
      directoryProvider: _FixedModelDirectoryProvider(modelDirectory),
      diskCapacityGateway: capacityGateway ?? diskCapacity,
      downloader: downloader ?? HttpModelArtifactDownloader(),
      checksumVerifier: const IsolateModelChecksumVerifier(),
      commentGenerator: commentGenerator ?? generator,
    );
  }

  void observe(VerifiedQwenModelStore target) {
    publishedStates = [];
    stateSubscription = target.states.listen(publishedStates.add);
  }

  File verifiedFile() {
    return File(
      '${modelDirectory.path}${Platform.pathSeparator}tiny-qwen.gguf',
    );
  }

  File partialFile() => File('${verifiedFile().path}.part');

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('pov_model_store_test.');
    modelDirectory = Directory(
      '${sandbox.path}${Platform.pathSeparator}models',
    );
    server = (await _LoopbackArtifactServer.start())..handler = (request) => _respondWithBytes(request, payload);
    diskCapacity = _FakeDiskCapacityGateway(
      available: payload.length + reserveBytes,
    );
    generator = _FakeCommentGenerator();
    store = createStore();
    observe(store);
  });

  tearDown(() async {
    await stateSubscription.cancel();
    await store.close();
    await server.close();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('downloads, verifies, atomically publishes, and loads the artifact', () async {
    final result = await store.prepare();

    expect(result, isA<AppSuccess<VerifiedModelArtifact>>());
    final artifact = (result as AppSuccess<VerifiedModelArtifact>).value;
    expect(File(artifact.filePath).readAsBytesSync(), payload);
    expect(File('${artifact.filePath}.part').existsSync(), isFalse);
    expect(generator.loadedArtifacts, [artifact]);
    expect(server.requestCount, 1);
    expect(diskCapacity.calls, 1);
    expect(publishedStates.first.phase, ModelStorePhase.loading);
    expect(
      publishedStates.map((state) => state.phase),
      containsAllInOrder([
        ModelStorePhase.downloading,
        ModelStorePhase.verifying,
        ModelStorePhase.loading,
        ModelStorePhase.ready,
      ]),
    );

    final progress = publishedStates
        .where((state) => state.phase == ModelStorePhase.downloading)
        .map((state) => state.downloadProgress!)
        .toList();
    expect(progress.first, 0);
    expect(progress.last, 1);
    expect(_isStrictlyIncreasing(progress), isTrue);
  });

  test('reuses a verified cache without network or capacity access', () async {
    final firstResult = await store.prepare();
    final artifact = (firstResult as AppSuccess<VerifiedModelArtifact>).value;
    final offlineManifest = manifest();
    File('${artifact.filePath}.part').writeAsBytesSync([9, 9, 9]);

    await stateSubscription.cancel();
    await store.close();
    await server.close();

    generator = _FakeCommentGenerator();
    store = createStore(
      artifactManifest: offlineManifest,
      capacityGateway: _FailingDiskCapacityGateway(),
    );
    observe(store);
    final cachedResult = await store.prepare();

    expect(cachedResult, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(generator.loadedArtifacts, hasLength(1));
    expect(File('${artifact.filePath}.part').existsSync(), isFalse);
    expect(
      publishedStates.map((state) => state.phase),
      [
        ModelStorePhase.loading,
        ModelStorePhase.verifying,
        ModelStorePhase.loading,
        ModelStorePhase.ready,
      ],
    );
  });

  test('rejects bad checksum bytes and removes every incomplete file', () async {
    await stateSubscription.cancel();
    store = createStore(artifactManifest: manifest(digest: '0' * 64));
    observe(store);

    final result = await store.prepare();

    expect(result, isA<AppError<VerifiedModelArtifact>>());
    expect(
      (result as AppError<VerifiedModelArtifact>).failure,
      isA<ValidationFailure>().having(
        (failure) => failure.code,
        'code',
        'model_integrity',
      ),
    );
    expect(verifiedFile().existsSync(), isFalse);
    expect(partialFile().existsSync(), isFalse);
    expect(generator.loadedArtifacts, isEmpty);
    expect(store.current.phase, ModelStorePhase.failure);
  });

  test('fails before transport when the retained free-space budget is unavailable', () async {
    diskCapacity.available = payload.length + reserveBytes - 1;

    final result = await store.prepare();

    expect(result, isA<AppError<VerifiedModelArtifact>>());
    expect(
      (result as AppError<VerifiedModelArtifact>).failure,
      isA<CacheFailure>().having(
        (failure) => failure.code,
        'code',
        'model_insufficient_storage',
      ),
    );
    expect(server.requestCount, 0);
    expect(partialFile().existsSync(), isFalse);
  });

  test('normalizes an HTTP failure and retries with a fresh staging file', () async {
    server.handler = (request) async {
      if (server.requestCount == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      await _respondWithBytes(request, payload);
    };

    final failed = await store.prepare();
    final retried = await store.prepare();

    expect(failed, isA<AppError<VerifiedModelArtifact>>());
    expect(
      (failed as AppError<VerifiedModelArtifact>).failure,
      isA<ServerFailure>().having(
        (failure) => failure.code,
        'code',
        'model_host_response',
      ),
    );
    expect(retried, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(server.requestCount, 2);
    expect(partialFile().existsSync(), isFalse);
  });

  test('normalizes unavailable network before it crosses the data boundary', () async {
    await server.close();

    final result = await store.prepare();

    expect(result, isA<AppError<VerifiedModelArtifact>>());
    expect(
      (result as AppError<VerifiedModelArtifact>).failure,
      isA<NetworkFailure>().having(
        (failure) => failure.code,
        'code',
        'model_download',
      ),
    );
    expect(partialFile().existsSync(), isFalse);
  });

  test('times out a connected server that stalls between body chunks', () async {
    final firstChunkSent = Completer<void>();
    final releaseResponse = Completer<void>();
    server.handler = (request) async {
      final response = request.response
        ..contentLength = payload.length
        ..add(payload.sublist(0, payload.length ~/ 2));
      await response.flush();
      firstChunkSent.complete();
      await releaseResponse.future;
      response.add(payload.sublist(payload.length ~/ 2));
      await response.close();
    };
    await stateSubscription.cancel();
    await store.close();
    generator = _FakeCommentGenerator();
    store = createStore(
      downloader: HttpModelArtifactDownloader(
        responseTimeout: const Duration(seconds: 1),
        bodyIdleTimeout: const Duration(milliseconds: 100),
      ),
    );
    observe(store);

    final preparation = store.prepare();
    await firstChunkSent.future;
    final result = await preparation.timeout(const Duration(seconds: 3));
    releaseResponse.complete();

    expect(result, isA<AppError<VerifiedModelArtifact>>());
    expect(
      (result as AppError<VerifiedModelArtifact>).failure,
      isA<NetworkFailure>().having(
        (failure) => failure.code,
        'code',
        'model_download',
      ),
    );
    expect(partialFile().existsSync(), isFalse);
  });

  test('shares one active preparation across concurrent callers', () async {
    final requestArrived = Completer<void>();
    final releaseResponse = Completer<void>();
    server.handler = (request) async {
      requestArrived.complete();
      await releaseResponse.future;
      await _respondWithBytes(request, payload);
    };

    final first = store.prepare();
    final second = store.prepare();
    await requestArrived.future;
    expect(identical(first, second), isTrue);
    expect(server.requestCount, 1);

    releaseResponse.complete();
    expect(await first, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(await second, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(generator.loadedArtifacts, hasLength(1));
  });

  test('installs the shared task before synchronous loading publication', () async {
    await stateSubscription.cancel();
    Future<AppResult<VerifiedModelArtifact>>? reentrantPreparation;
    stateSubscription = store.states.listen((state) {
      publishedStates.add(state);
      if (state.phase == ModelStorePhase.loading && reentrantPreparation == null) {
        reentrantPreparation = store.prepare();
      }
    });

    final primaryPreparation = store.prepare();
    final reentrant = reentrantPreparation;

    expect(reentrant, isNotNull);
    expect(identical(primaryPreparation, reentrant), isTrue);
    expect(await primaryPreparation, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(await reentrant, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(server.requestCount, 1);
    expect(generator.loadedArtifacts, hasLength(1));
  });

  test('suspend cancels transport, removes partial bytes, and suppresses stale state', () async {
    await stateSubscription.cancel();
    await store.close();
    generator = _FakeCommentGenerator();
    final blockingDownloader = _BlockingModelArtifactDownloader(payload);
    store = createStore(downloader: blockingDownloader);
    observe(store);

    final preparation = store.prepare();
    await blockingDownloader.started.future;
    await store.suspend().timeout(const Duration(seconds: 5));
    final result = await preparation;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(result, isA<AppError<VerifiedModelArtifact>>());
    expect(store.current.phase, ModelStorePhase.suspended);
    expect(publishedStates.last.phase, ModelStorePhase.suspended);
    expect(
      publishedStates.skipWhile((state) => state.phase != ModelStorePhase.suspended).skip(1),
      isEmpty,
    );
    expect(partialFile().existsSync(), isFalse);
    expect(generator.unloadCalls, greaterThanOrEqualTo(1));
  });

  test('suspend rejects a native load completion that crossed invalidation', () async {
    generator.loadGate = Completer<AppResult<void>>();
    final preparation = store.prepare();
    await generator.loadStarted.future;
    expect(store.current.phase, ModelStorePhase.loading);

    final suspension = store.suspend();
    await suspension.timeout(const Duration(seconds: 5));
    final result = await preparation;

    expect(result, isA<AppError<VerifiedModelArtifact>>());
    expect(store.current.phase, ModelStorePhase.suspended);
    expect(publishedStates.where((state) => state.phase == ModelStorePhase.ready), isEmpty);
    expect(verifiedFile().existsSync(), isTrue);

    final retried = await store.prepare();
    expect(retried, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(store.current.phase, ModelStorePhase.ready);
    expect(generator.loadedArtifacts, hasLength(2));
  });

  test('queues reentrant prepare until suspended resources are unloaded', () async {
    expect(await store.prepare(), isA<AppSuccess<VerifiedModelArtifact>>());
    expect(generator.isLoaded, isTrue);
    await stateSubscription.cancel();
    Future<AppResult<VerifiedModelArtifact>>? queuedPreparation;
    stateSubscription = store.states.listen((state) {
      publishedStates.add(state);
      if (state.phase == ModelStorePhase.suspended && queuedPreparation == null) {
        queuedPreparation = store.prepare();
      }
    });

    await store.suspend();
    final queued = queuedPreparation;

    expect(queued, isNotNull);
    expect(await queued, isA<AppSuccess<VerifiedModelArtifact>>());
    expect(store.current.phase, ModelStorePhase.ready);
    expect(generator.isLoaded, isTrue);
    expect(generator.loadedArtifacts, hasLength(2));
    expect(server.requestCount, 1);
  });

  test('close cancels an active download and closes the state stream', () async {
    final streamDone = Completer<void>();
    await stateSubscription.cancel();
    await store.close();
    generator = _FakeCommentGenerator();
    final blockingDownloader = _BlockingModelArtifactDownloader(payload);
    store = createStore(downloader: blockingDownloader);
    stateSubscription = store.states.listen(
      (_) {},
      onDone: streamDone.complete,
    );

    final preparation = store.prepare();
    await blockingDownloader.started.future;
    await store.close().timeout(const Duration(seconds: 5));

    expect(await preparation, isA<AppError<VerifiedModelArtifact>>());
    await streamDone.future;
    expect(partialFile().existsSync(), isFalse);
    expect(
      await store.prepare(),
      isA<AppError<VerifiedModelArtifact>>().having(
        (result) => result.failure.code,
        'failure code',
        'model_store_closed',
      ),
    );
  });
}

bool _isStrictlyIncreasing(List<double> values) {
  for (var index = 1; index < values.length; index += 1) {
    if (values[index] <= values[index - 1]) return false;
  }
  return true;
}

Future<void> _respondWithBytes(HttpRequest request, Uint8List bytes) async {
  request.response.contentLength = bytes.length;
  request.response.add(bytes);
  await request.response.close();
}

final class _LoopbackArtifactServer {
  _LoopbackArtifactServer._(this._server) {
    _server.listen((request) async {
      requestCount += 1;
      try {
        await handler(request);
      } on HttpException {
        // Client cancellation is expected in suspend and close scenarios.
      } on SocketException {
        // Client cancellation is expected in suspend and close scenarios.
      }
    });
  }

  static Future<_LoopbackArtifactServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _LoopbackArtifactServer._(server);
  }

  final HttpServer _server;
  late Future<void> Function(HttpRequest request) handler;
  int requestCount = 0;

  Uri get uri => Uri.parse('http://${_server.address.host}:${_server.port}/model.gguf');

  Future<void> close() => _server.close(force: true);
}

final class _FixedModelDirectoryProvider implements ModelDirectoryProvider {
  const _FixedModelDirectoryProvider(this.directory);

  final Directory directory;

  @override
  Future<Directory> resolve() async => directory;
}

final class _FakeDiskCapacityGateway implements ModelDiskCapacityGateway {
  _FakeDiskCapacityGateway({required this.available});

  int available;
  int calls = 0;

  @override
  Future<int> availableBytes(String directoryPath) async {
    calls += 1;
    return available;
  }
}

final class _FailingDiskCapacityGateway implements ModelDiskCapacityGateway {
  @override
  Future<int> availableBytes(String directoryPath) {
    throw StateError('A verified cache must not require a capacity check.');
  }
}

final class _FakeCommentGenerator implements CommentGenerator {
  final List<VerifiedModelArtifact> loadedArtifacts = [];
  final Completer<void> loadStarted = Completer<void>();
  Completer<AppResult<void>>? loadGate;
  int unloadCalls = 0;
  bool isLoaded = false;

  @override
  Future<AppResult<void>> loadModel(VerifiedModelArtifact artifact) async {
    loadedArtifacts.add(artifact);
    if (!loadStarted.isCompleted) loadStarted.complete();
    final result = await (loadGate?.future ?? Future.value(const AppSuccess<void>(null)));
    if (result is AppSuccess<void>) isLoaded = true;
    return result;
  }

  @override
  Future<AppResult<GenerationHandle>> generate(CommentGenerationRequest request) async {
    return const AppError(
      UnexpectedFailure(code: 'generation_not_used_by_model_store_test'),
    );
  }

  @override
  Future<void> unload() async {
    unloadCalls += 1;
    isLoaded = false;
    final gate = loadGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete(const AppSuccess<void>(null));
    }
  }

  @override
  Future<void> close() => unload();
}

final class _BlockingModelArtifactDownloader implements ModelArtifactDownloader {
  _BlockingModelArtifactDownloader(this.bytes);

  final Uint8List bytes;
  final Completer<void> started = Completer<void>();

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) async {
    final firstHalf = bytes.sublist(0, bytes.length ~/ 2);
    File(destinationPath).writeAsBytesSync(firstHalf);
    onProgress(firstHalf.length);
    started.complete();

    final cancelled = Completer<void>();
    final removeListener = cancellation.addListener(cancelled.complete);
    await cancelled.future;
    removeListener();
    throw const ModelDownloadCancelledException();
  }
}
