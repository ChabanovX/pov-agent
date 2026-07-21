import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';
import 'package:pov_agent/features/assistant/data/models/piper_model_manifest.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_piper_model_store.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  const reserveBytes = 64;

  late Directory sandbox;
  late Directory modelDirectory;
  late _TinyPiperArchive fixture;
  late _LoopbackArchiveServer server;
  late _RecordingDiskCapacityGateway diskCapacity;
  late List<VerifiedPiperModelStore> stores;
  late List<StreamSubscription<Object?>> subscriptions;

  PiperModelManifest manifest({String? archiveSha256}) {
    return PiperModelManifest(
      modelId: 'test/tiny-piper',
      downloadUrl: server.uri.toString(),
      revision: 'test-revision',
      archiveFilename: _TinyPiperArchive.archiveFilename,
      archiveByteSize: fixture.archiveBytes.length,
      archiveSha256: archiveSha256 ?? sha256.convert(fixture.archiveBytes).toString(),
      expandedArchiveByteSize: fixture.tarByteSize,
      extractedByteSize: fixture.extractedByteSize,
      extractedFileCount: fixture.files.length,
      bundleTreeSha256: fixture.treeSha256,
      archiveRoot: _TinyPiperArchive.rootName,
      modelFilename: _TinyPiperArchive.modelFilename,
      tokensFilename: _TinyPiperArchive.tokensFilename,
      espeakDataDirectory: _TinyPiperArchive.espeakDirectory,
      license: 'test-only',
      downloadReserveBytes: reserveBytes,
    );
  }

  VerifiedPiperModelStore createStore({
    PiperModelManifest? bundleManifest,
    ModelDiskCapacityGateway? capacityGateway,
    ModelArtifactDownloader? downloader,
    PiperBundleExtractor? extractor,
    PiperBundleVerifier? verifier,
  }) {
    final store = VerifiedPiperModelStore(
      manifest: bundleManifest ?? manifest(),
      directoryProvider: _FixedModelDirectoryProvider(modelDirectory),
      diskCapacityGateway: capacityGateway ?? diskCapacity,
      downloader: downloader ?? HttpModelArtifactDownloader(),
      checksumVerifier: const IsolateModelChecksumVerifier(),
      bundleExtractor: extractor ?? const IsolatePiperBundleExtractor(),
      bundleVerifier: verifier ?? const IsolatePiperBundleVerifier(),
    );
    stores.add(store);
    return store;
  }

  File cachedArchive() {
    return File(
      '${modelDirectory.path}${Platform.pathSeparator}'
      '${_TinyPiperArchive.archiveFilename}',
    );
  }

  File partialArchive() => File('${cachedArchive().path}.part');

  Directory publishedBundle() {
    return Directory(
      '${modelDirectory.path}${Platform.pathSeparator}'
      '${_TinyPiperArchive.rootName}',
    );
  }

  Directory stagingBundle() => Directory('${publishedBundle().path}.extracting');

  File expandedArchive() => File('${stagingBundle().path}.tar');

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('pov_piper_store_test.');
    modelDirectory = Directory(
      '${sandbox.path}${Platform.pathSeparator}models',
    );
    fixture = _TinyPiperArchive.create();
    server = (await _LoopbackArchiveServer.start())
      ..handler = (request) => _respondWithBytes(request, fixture.archiveBytes);
    diskCapacity = _RecordingDiskCapacityGateway(
      available: fixture.archiveBytes.length + fixture.tarByteSize + fixture.extractedByteSize + reserveBytes,
    );
    stores = [];
    subscriptions = [];
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final store in stores.reversed) {
      await store.close();
    }
    await server.close();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('real extractor and verifier reconstruct the pinned tiny tree', () async {
    final archive = File(
      '${sandbox.path}${Platform.pathSeparator}'
      '${_TinyPiperArchive.archiveFilename}',
    );
    final extractionRoot = Directory(
      '${sandbox.path}${Platform.pathSeparator}extracted',
    );
    archive.writeAsBytesSync(fixture.archiveBytes);

    await const IsolatePiperBundleExtractor().extract(
      archivePath: archive.path,
      destinationPath: extractionRoot.path,
      temporaryTarPath: '${extractionRoot.path}.tar',
      expectedTarByteSize: fixture.tarByteSize,
    );
    final bundle = Directory(
      '${extractionRoot.path}${Platform.pathSeparator}'
      '${_TinyPiperArchive.rootName}',
    );
    final verification = await const IsolatePiperBundleVerifier().verify(
      bundle.path,
    );

    expect(verification.byteSize, fixture.extractedByteSize);
    expect(verification.fileCount, fixture.files.length);
    expect(verification.treeSha256, fixture.treeSha256);
    for (final entry in fixture.files.entries) {
      final path = entry.key.replaceAll('/', Platform.pathSeparator);
      expect(
        File('${bundle.path}${Platform.pathSeparator}$path').readAsBytesSync(),
        entry.value,
      );
    }
  });

  test('bundle verifier rejects a symlinked cache root', () async {
    final target = Directory(
      '${sandbox.path}${Platform.pathSeparator}outside-bundle',
    )..createSync();
    File(
      '${target.path}${Platform.pathSeparator}voice.onnx',
    ).writeAsStringSync('outside');
    final linkedRoot = Link(
      '${sandbox.path}${Platform.pathSeparator}linked-bundle',
    )..createSync(target.path);

    await expectLater(
      const IsolatePiperBundleVerifier().verify(linkedRoot.path),
      throwsA(isA<ModelIntegrityException>()),
    );
  });

  test('extractor removes its expanded tar after integrity failure', () async {
    final archive = File(
      '${sandbox.path}${Platform.pathSeparator}'
      '${_TinyPiperArchive.archiveFilename}',
    )..writeAsBytesSync(fixture.archiveBytes);
    final extractionRoot = Directory(
      '${sandbox.path}${Platform.pathSeparator}failed-extraction',
    );
    final temporaryTar = File('${extractionRoot.path}.tar');

    await expectLater(
      const IsolatePiperBundleExtractor().extract(
        archivePath: archive.path,
        destinationPath: extractionRoot.path,
        temporaryTarPath: temporaryTar.path,
        expectedTarByteSize: fixture.tarByteSize + 1,
      ),
      throwsA(isA<ModelIntegrityException>()),
    );

    expect(temporaryTar.existsSync(), isFalse);
  });

  test(
    'cold preparation downloads, verifies, extracts, and atomically publishes',
    () async {
      final store = createStore();
      final states = <ModelStoreState<VerifiedPiperModelBundle>>[];
      subscriptions.add(store.states.listen(states.add));

      final result = await store.prepare();

      expect(result, isA<AppSuccess<VerifiedPiperModelBundle>>());
      final bundle = (result as AppSuccess<VerifiedPiperModelBundle>).value;
      expect(bundle.bundleDirectoryPath, publishedBundle().absolute.path);
      expect(File(bundle.modelFilePath).readAsBytesSync(), fixture.modelBytes);
      expect(File(bundle.tokensFilePath).readAsBytesSync(), fixture.tokensBytes);
      expect(Directory(bundle.espeakDataDirectoryPath).existsSync(), isTrue);
      expect(cachedArchive().readAsBytesSync(), fixture.archiveBytes);
      expect(partialArchive().existsSync(), isFalse);
      expect(expandedArchive().existsSync(), isFalse);
      expect(stagingBundle().existsSync(), isFalse);
      expect(server.requestCount, 1);
      expect(diskCapacity.calls, 1);
      expect(
        states.map((state) => state.phase),
        containsAllInOrder([
          ModelStorePhase.loading,
          ModelStorePhase.downloading,
          ModelStorePhase.verifying,
          ModelStorePhase.loading,
          ModelStorePhase.verifying,
          ModelStorePhase.ready,
        ]),
      );
      final progress = states
          .where((state) => state.phase == ModelStorePhase.downloading)
          .map((state) => state.downloadProgress!)
          .toList();
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(_isStrictlyIncreasing(progress), isTrue);

      final verification = await const IsolatePiperBundleVerifier().verify(
        bundle.bundleDirectoryPath,
      );
      expect(verification.treeSha256, fixture.treeSha256);
    },
  );

  test('capacity includes the expanded tar peak before transport', () async {
    final requiredBytes = fixture.archiveBytes.length + fixture.tarByteSize + fixture.extractedByteSize + reserveBytes;
    final store = createStore(
      capacityGateway: _RecordingDiskCapacityGateway(
        available: requiredBytes - 1,
      ),
    );

    final result = await store.prepare();

    expect(result, isA<AppError<VerifiedPiperModelBundle>>());
    expect(
      (result as AppError<VerifiedPiperModelBundle>).failure,
      isA<CacheFailure>().having(
        (failure) => failure.code,
        'code',
        'model_insufficient_storage',
      ),
    );
    expect(server.requestCount, 0);
    expect(expandedArchive().existsSync(), isFalse);
  });

  test('a new offline store reuses the verified archive and bundle', () async {
    final pinnedManifest = manifest();
    final firstStore = createStore(bundleManifest: pinnedManifest);
    expect(
      await firstStore.prepare(),
      isA<AppSuccess<VerifiedPiperModelBundle>>(),
    );
    await firstStore.close();
    await server.close();
    partialArchive()
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9, 9]);
    stagingBundle().createSync(recursive: true);
    File(
      '${stagingBundle().path}${Platform.pathSeparator}stale',
    ).writeAsStringSync('stale');
    expandedArchive().writeAsStringSync('stale expanded tar');

    final store = createStore(
      bundleManifest: pinnedManifest,
      capacityGateway: _FailingDiskCapacityGateway(),
      downloader: _FailingDownloader(),
    );
    final states = <ModelStoreState<VerifiedPiperModelBundle>>[];
    subscriptions.add(store.states.listen(states.add));
    final result = await store.prepare();

    expect(result, isA<AppSuccess<VerifiedPiperModelBundle>>());
    expect(server.requestCount, 1);
    expect(partialArchive().existsSync(), isFalse);
    expect(expandedArchive().existsSync(), isFalse);
    expect(stagingBundle().existsSync(), isFalse);
    expect(
      states.map((state) => state.phase),
      [
        ModelStorePhase.loading,
        ModelStorePhase.verifying,
        ModelStorePhase.verifying,
        ModelStorePhase.ready,
      ],
    );
  });

  test(
    'a corrupt extracted bundle is rebuilt from the verified archive offline',
    () async {
      final pinnedManifest = manifest();
      final firstStore = createStore(bundleManifest: pinnedManifest);
      expect(
        await firstStore.prepare(),
        isA<AppSuccess<VerifiedPiperModelBundle>>(),
      );
      await firstStore.close();
      await server.close();
      final tokens = File(
        '${publishedBundle().path}${Platform.pathSeparator}'
        '${_TinyPiperArchive.tokensFilename}',
      )..writeAsStringSync('corrupt');
      final offlineCapacity = _RecordingDiskCapacityGateway(
        available: fixture.tarByteSize + fixture.extractedByteSize + reserveBytes,
      );

      final store = createStore(
        bundleManifest: pinnedManifest,
        capacityGateway: offlineCapacity,
        downloader: _FailingDownloader(),
      );
      final result = await store.prepare();

      expect(result, isA<AppSuccess<VerifiedPiperModelBundle>>());
      expect(tokens.readAsBytesSync(), fixture.tokensBytes);
      expect(cachedArchive().readAsBytesSync(), fixture.archiveBytes);
      expect(server.requestCount, 1);
      expect(offlineCapacity.calls, 1);
      expect(expandedArchive().existsSync(), isFalse);
      expect(stagingBundle().existsSync(), isFalse);
    },
  );

  test('a corrupt archive forces a fresh download and bundle rebuild', () async {
    final pinnedManifest = manifest();
    final firstStore = createStore(bundleManifest: pinnedManifest);
    expect(
      await firstStore.prepare(),
      isA<AppSuccess<VerifiedPiperModelBundle>>(),
    );
    await firstStore.close();
    final corruptArchiveBytes = cachedArchive().readAsBytesSync();
    corruptArchiveBytes[corruptArchiveBytes.length ~/ 2] ^= 0xff;
    cachedArchive().writeAsBytesSync(corruptArchiveBytes);
    final marker = File(
      '${publishedBundle().path}${Platform.pathSeparator}stale-marker',
    )..writeAsStringSync('must be replaced');

    final store = createStore(bundleManifest: pinnedManifest);
    final result = await store.prepare();

    expect(result, isA<AppSuccess<VerifiedPiperModelBundle>>());
    expect(server.requestCount, 2);
    expect(cachedArchive().readAsBytesSync(), fixture.archiveBytes);
    expect(marker.existsSync(), isFalse);
    expect(expandedArchive().existsSync(), isFalse);
    expect(stagingBundle().existsSync(), isFalse);
  });

  test('integrity failure removes every incomplete filesystem entry', () async {
    final store = createStore(
      bundleManifest: manifest(archiveSha256: '0' * 64),
    );
    partialArchive()
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    stagingBundle().createSync(recursive: true);
    File(
      '${stagingBundle().path}${Platform.pathSeparator}stale',
    ).writeAsStringSync('stale');
    expandedArchive().writeAsStringSync('stale expanded tar');

    final result = await store.prepare();

    expect(result, isA<AppError<VerifiedPiperModelBundle>>());
    expect(
      (result as AppError<VerifiedPiperModelBundle>).failure,
      isA<ValidationFailure>().having(
        (failure) => failure.code,
        'code',
        'model_integrity',
      ),
    );
    expect(cachedArchive().existsSync(), isFalse);
    expect(partialArchive().existsSync(), isFalse);
    expect(expandedArchive().existsSync(), isFalse);
    expect(stagingBundle().existsSync(), isFalse);
    expect(publishedBundle().existsSync(), isFalse);
  });

  test(
    'suspend cancels real HTTP transport and suppresses stale completion state',
    () async {
      final firstChunkSent = Completer<void>();
      final releaseResponse = Completer<void>();
      server.handler = (request) async {
        final split = fixture.archiveBytes.length ~/ 2;
        final response = request.response
          ..contentLength = fixture.archiveBytes.length
          ..add(fixture.archiveBytes.sublist(0, split));
        await response.flush();
        firstChunkSent.complete();
        await releaseResponse.future;
        response.add(fixture.archiveBytes.sublist(split));
        await response.close();
      };
      final store = createStore();
      final states = <ModelStoreState<VerifiedPiperModelBundle>>[];
      subscriptions.add(store.states.listen(states.add));

      final preparation = store.prepare();
      await firstChunkSent.future.timeout(const Duration(seconds: 5));
      await store.suspend().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw StateError(
            'Suspension did not settle from ${store.current.phase}.',
          );
        },
      );
      final result = await preparation;
      releaseResponse.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result, isA<AppError<VerifiedPiperModelBundle>>());
      expect(
        (result as AppError<VerifiedPiperModelBundle>).failure.code,
        'model_preparation_cancelled',
      );
      expect(store.current.phase, ModelStorePhase.suspended);
      expect(states.last.phase, ModelStorePhase.suspended);
      expect(
        states.skipWhile((state) => state.phase != ModelStorePhase.suspended).skip(1),
        isEmpty,
      );
      expect(partialArchive().existsSync(), isFalse);
      expect(expandedArchive().existsSync(), isFalse);
      expect(stagingBundle().existsSync(), isFalse);
      expect(cachedArchive().existsSync(), isFalse);
    },
  );

  test(
    'close waits for non-cancellable extraction and removes its staging tree',
    () async {
      final gatedExtractor = _GatedPiperBundleExtractor(
        const IsolatePiperBundleExtractor(),
      );
      final store = createStore(extractor: gatedExtractor);
      final streamDone = Completer<void>();
      subscriptions.add(store.states.listen((_) {}, onDone: streamDone.complete));

      final preparation = store.prepare();
      await gatedExtractor.started.future.timeout(const Duration(seconds: 5));
      var closeCompleted = false;
      final closeTask = store.close().whenComplete(() => closeCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(closeCompleted, isFalse);
      expect(stagingBundle().existsSync(), isTrue);
      gatedExtractor.release.complete();
      await closeTask.timeout(const Duration(seconds: 5));
      final result = await preparation;

      expect(result, isA<AppError<VerifiedPiperModelBundle>>());
      expect(
        (result as AppError<VerifiedPiperModelBundle>).failure.code,
        'model_preparation_cancelled',
      );
      await streamDone.future;
      expect(stagingBundle().existsSync(), isFalse);
      expect(partialArchive().existsSync(), isFalse);
      expect(expandedArchive().existsSync(), isFalse);
      expect(publishedBundle().existsSync(), isFalse);
      expect(cachedArchive().existsSync(), isTrue);
      expect(
        await store.prepare(),
        isA<AppError<VerifiedPiperModelBundle>>().having(
          (result) => result.failure.code,
          'failure code',
          'piper_model_store_closed',
        ),
      );
    },
  );

  test('concrete store retries cleanup after close fails', () async {
    final verifier = _GatedErrorPiperBundleVerifier();
    final store = createStore(verifier: verifier);
    final preparation = store.prepare();
    final preparationExpectation = expectLater(
      preparation,
      throwsA(isA<StateError>()),
    );
    await verifier.started.future.timeout(const Duration(seconds: 5));

    final firstClose = store.close();
    verifier.release.complete();

    await expectLater(firstClose, throwsA(isA<StateError>()));
    await preparationExpectation;
    await expectLater(store.close(), completes);
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

final class _TinyPiperArchive {
  _TinyPiperArchive._({
    required this.files,
    required this.archiveBytes,
    required this.tarByteSize,
    required this.extractedByteSize,
    required this.treeSha256,
  });

  factory _TinyPiperArchive.create() {
    final files = <String, Uint8List>{
      modelFilename: Uint8List.fromList(
        List<int>.generate(73, (index) => (index * 19) % 256),
      ),
      tokensFilename: Uint8List.fromList(utf8.encode('_ 0\na 1\nb 2\n')),
      '$espeakDirectory/phondata': Uint8List.fromList(
        List<int>.generate(37, (index) => (index * 7 + 3) % 256),
      ),
      '$espeakDirectory/en_dict': Uint8List.fromList(
        utf8.encode('tiny deterministic dictionary'),
      ),
    };
    final archive = Archive()
      ..add(ArchiveFile.directory('$rootName/'))
      ..add(ArchiveFile.directory('$rootName/$espeakDirectory/'));
    for (final entry in files.entries) {
      archive.add(ArchiveFile.bytes('$rootName/${entry.key}', entry.value));
    }
    final tarBytes = TarEncoder().encodeBytes(archive);
    final archiveBytes = BZip2Encoder().encodeBytes(tarBytes);
    final sortedPaths = files.keys.toList()..sort();
    final canonicalRecords = StringBuffer();
    for (final path in sortedPaths) {
      canonicalRecords
        ..write(sha256.convert(files[path]!))
        ..write('  ')
        ..write(path)
        ..write('\n');
    }
    return _TinyPiperArchive._(
      files: files,
      archiveBytes: archiveBytes,
      tarByteSize: tarBytes.length,
      extractedByteSize: files.values.fold(
        0,
        (sum, bytes) => sum + bytes.length,
      ),
      treeSha256: sha256.convert(utf8.encode(canonicalRecords.toString())).toString(),
    );
  }

  static const archiveFilename = 'tiny-piper.tar.bz2';
  static const rootName = 'tiny-piper';
  static const modelFilename = 'voice.onnx';
  static const tokensFilename = 'tokens.txt';
  static const espeakDirectory = 'espeak-ng-data';

  final Map<String, Uint8List> files;
  final Uint8List archiveBytes;
  final int tarByteSize;
  final int extractedByteSize;
  final String treeSha256;

  Uint8List get modelBytes => files[modelFilename]!;

  Uint8List get tokensBytes => files[tokensFilename]!;
}

final class _LoopbackArchiveServer {
  _LoopbackArchiveServer._(this._server) {
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

  static Future<_LoopbackArchiveServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _LoopbackArchiveServer._(server);
  }

  final HttpServer _server;
  late Future<void> Function(HttpRequest request) handler;
  int requestCount = 0;
  var _isClosed = false;

  Uri get uri {
    return Uri.parse(
      'http://${_server.address.host}:${_server.port}/$archiveFilename',
    );
  }

  String get archiveFilename => _TinyPiperArchive.archiveFilename;

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _server.close(force: true);
  }
}

final class _FixedModelDirectoryProvider implements ModelDirectoryProvider {
  const _FixedModelDirectoryProvider(this.directory);

  final Directory directory;

  @override
  Future<Directory> resolve() async => directory;
}

final class _RecordingDiskCapacityGateway implements ModelDiskCapacityGateway {
  _RecordingDiskCapacityGateway({required this.available});

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
    throw StateError('A complete verified cache must skip capacity checks.');
  }
}

final class _FailingDownloader implements ModelArtifactDownloader {
  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) {
    throw StateError('A verified archive must be reusable without transport.');
  }
}

final class _GatedPiperBundleExtractor implements PiperBundleExtractor {
  _GatedPiperBundleExtractor(this._delegate);

  final PiperBundleExtractor _delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> extract({
    required String archivePath,
    required String destinationPath,
    required String temporaryTarPath,
    required int expectedTarByteSize,
  }) async {
    final staging = Directory(destinationPath)..createSync(recursive: true);
    File(
      '${staging.path}${Platform.pathSeparator}in-progress',
    ).writeAsStringSync('extraction is active');
    started.complete();
    await release.future;
    await _delegate.extract(
      archivePath: archivePath,
      destinationPath: destinationPath,
      temporaryTarPath: temporaryTarPath,
      expectedTarByteSize: expectedTarByteSize,
    );
  }
}

final class _GatedErrorPiperBundleVerifier implements PiperBundleVerifier {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<PiperBundleVerification> verify(String bundleDirectoryPath) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    throw StateError('simulated verifier teardown race');
  }
}
