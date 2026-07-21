import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/models/asr_model_manifest.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_asr_model_store.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  const reserveBytes = 64;

  late Directory sandbox;
  late Directory modelDirectory;
  late _TinyAsrArchive fixture;
  late _LoopbackArchiveServer server;
  late _RecordingDiskCapacityGateway diskCapacity;
  late List<VerifiedAsrModelStore> stores;

  AsrModelManifest manifest({
    String? archiveSha256,
    String modelFilename = _TinyAsrArchive.modelFilename,
    String tokensFilename = _TinyAsrArchive.tokensFilename,
  }) {
    return AsrModelManifest(
      modelId: 'test/tiny-streaming-asr',
      downloadUrl: server.uri.toString(),
      revision: 'test-revision',
      archiveFilename: _TinyAsrArchive.archiveFilename,
      archiveByteSize: fixture.archiveBytes.length,
      archiveSha256: archiveSha256 ?? sha256.convert(fixture.archiveBytes).toString(),
      expandedArchiveByteSize: fixture.tarByteSize,
      extractedByteSize: fixture.extractedByteSize,
      extractedFileCount: fixture.files.length,
      bundleTreeSha256: fixture.treeSha256,
      archiveRoot: _TinyAsrArchive.rootName,
      modelFilename: modelFilename,
      tokensFilename: tokensFilename,
      license: 'test-only',
      downloadReserveBytes: reserveBytes,
    );
  }

  VerifiedAsrModelStore createStore({
    AsrModelManifest? bundleManifest,
    ModelDiskCapacityGateway? capacityGateway,
    ModelArtifactDownloader? downloader,
    ModelBundleVerifier? verifier,
  }) {
    final store = VerifiedAsrModelStore(
      manifest: bundleManifest ?? manifest(),
      directoryProvider: _FixedModelDirectoryProvider(modelDirectory),
      diskCapacityGateway: capacityGateway ?? diskCapacity,
      downloader: downloader ?? HttpModelArtifactDownloader(),
      checksumVerifier: const IsolateModelChecksumVerifier(),
      bundleExtractor: const IsolateModelBundleExtractor(),
      bundleVerifier: verifier ?? const IsolateModelBundleVerifier(),
    );
    stores.add(store);
    return store;
  }

  File cachedArchive() {
    return File(
      '${modelDirectory.path}${Platform.pathSeparator}'
      '${_TinyAsrArchive.archiveFilename}',
    );
  }

  File partialArchive() => File('${cachedArchive().path}.part');

  Directory publishedBundle() {
    return Directory(
      '${modelDirectory.path}${Platform.pathSeparator}'
      '${_TinyAsrArchive.rootName}',
    );
  }

  Directory stagingBundle() => Directory('${publishedBundle().path}.extracting');

  File expandedArchive() => File('${stagingBundle().path}.tar');

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('pov_asr_store_test.');
    modelDirectory = Directory(
      '${sandbox.path}${Platform.pathSeparator}models',
    );
    fixture = _TinyAsrArchive.create();
    server = (await _LoopbackArchiveServer.start())
      ..handler = (request) => _respondWithBytes(request, fixture.archiveBytes);
    diskCapacity = _RecordingDiskCapacityGateway(
      available: fixture.archiveBytes.length + fixture.tarByteSize + fixture.extractedByteSize + reserveBytes,
    );
    stores = [];
  });

  tearDown(() async {
    for (final store in stores.reversed) {
      await store.close();
    }
    await server.close();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('generic extractor rejects traversal and removes its expanded tar', () async {
    final archive = Archive()..add(ArchiveFile.bytes('../outside.txt', utf8.encode('escape')));
    final tarBytes = TarEncoder().encodeBytes(archive);
    final archiveFile = File(
      '${sandbox.path}${Platform.pathSeparator}traversal.tar.bz2',
    )..writeAsBytesSync(BZip2Encoder().encodeBytes(tarBytes));
    final destination = Directory(
      '${sandbox.path}${Platform.pathSeparator}traversal-staging',
    );
    final temporaryTar = File('${destination.path}.tar');

    await expectLater(
      const IsolateModelBundleExtractor().extract(
        archivePath: archiveFile.path,
        destinationPath: destination.path,
        temporaryTarPath: temporaryTar.path,
        expectedTarByteSize: tarBytes.length,
      ),
      throwsA(isA<ModelIntegrityException>()),
    );

    expect(
      File('${sandbox.path}${Platform.pathSeparator}outside.txt').existsSync(),
      isFalse,
    );
    expect(temporaryTar.existsSync(), isFalse);
  });

  test(
    'loopback cold download verifies the full tree before atomic publish',
    () async {
      final verifier = _GatedModelBundleVerifier(
        const IsolateModelBundleVerifier(),
      );
      final store = createStore(verifier: verifier);
      final states = <ModelStoreState<VerifiedAsrModelBundle>>[];
      final subscription = store.states.listen(states.add);
      addTearDown(subscription.cancel);

      final preparation = store.prepare();
      await verifier.started.future.timeout(const Duration(seconds: 5));

      expect(publishedBundle().existsSync(), isFalse);
      expect(
        Directory(
          '${stagingBundle().path}${Platform.pathSeparator}'
          '${_TinyAsrArchive.rootName}',
        ).existsSync(),
        isTrue,
      );
      verifier.release.complete();

      final result = await preparation.timeout(const Duration(seconds: 5));

      expect(result, isA<AppSuccess<VerifiedAsrModelBundle>>());
      final bundle = (result as AppSuccess<VerifiedAsrModelBundle>).value;
      expect(bundle.bundleDirectoryPath, publishedBundle().absolute.path);
      expect(File(bundle.modelFilePath).readAsBytesSync(), fixture.modelBytes);
      expect(File(bundle.tokensFilePath).readAsBytesSync(), fixture.tokensBytes);
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
      final verification = await const IsolateModelBundleVerifier().verify(
        bundle.bundleDirectoryPath,
      );
      expect(verification.treeSha256, fixture.treeSha256);
    },
  );

  test(
    'verified archive supports offline cache reuse and corrupt-tree rebuild',
    () async {
      final pinnedManifest = manifest();
      final firstStore = createStore(bundleManifest: pinnedManifest);
      expect(
        await firstStore.prepare(),
        isA<AppSuccess<VerifiedAsrModelBundle>>(),
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

      final cachedStore = createStore(
        bundleManifest: pinnedManifest,
        capacityGateway: _FailingDiskCapacityGateway(),
        downloader: _FailingDownloader(),
      );
      expect(
        await cachedStore.prepare(),
        isA<AppSuccess<VerifiedAsrModelBundle>>(),
      );
      await cachedStore.close();
      expect(partialArchive().existsSync(), isFalse);
      expect(expandedArchive().existsSync(), isFalse);
      expect(stagingBundle().existsSync(), isFalse);

      final model = File(
        '${publishedBundle().path}${Platform.pathSeparator}'
        '${_TinyAsrArchive.modelFilename}',
      )..writeAsStringSync('corrupt');
      final rebuildCapacity = _RecordingDiskCapacityGateway(
        available: fixture.tarByteSize + fixture.extractedByteSize + reserveBytes,
      );
      final rebuiltStore = createStore(
        bundleManifest: pinnedManifest,
        capacityGateway: rebuildCapacity,
        downloader: _FailingDownloader(),
      );

      expect(
        await rebuiltStore.prepare(),
        isA<AppSuccess<VerifiedAsrModelBundle>>(),
      );
      expect(model.readAsBytesSync(), fixture.modelBytes);
      expect(cachedArchive().readAsBytesSync(), fixture.archiveBytes);
      expect(server.requestCount, 1);
      expect(rebuildCapacity.calls, 1);
      expect(expandedArchive().existsSync(), isFalse);
      expect(stagingBundle().existsSync(), isFalse);
    },
  );

  test(
    'promotes a completed background archive before considering transport',
    () async {
      partialArchive()
        ..createSync(recursive: true)
        ..writeAsBytesSync(fixture.archiveBytes);
      final store = createStore(downloader: _FailingDownloader());

      final result = await store.prepare();

      expect(result, isA<AppSuccess<VerifiedAsrModelBundle>>());
      expect(cachedArchive().readAsBytesSync(), fixture.archiveBytes);
      expect(partialArchive().existsSync(), isFalse);
      expect(server.requestCount, 0);
      expect(diskCapacity.calls, 1);
    },
  );

  test('integrity failure removes every incomplete cache entry', () async {
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

    expect(result, isA<AppError<VerifiedAsrModelBundle>>());
    expect(
      (result as AppError<VerifiedAsrModelBundle>).failure,
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

  test('tree verification still requires the configured model and tokens', () async {
    for (final invalidManifest in [
      manifest(modelFilename: 'missing-model.onnx'),
      manifest(tokensFilename: 'missing-tokens.txt'),
    ]) {
      final store = createStore(bundleManifest: invalidManifest);

      final result = await store.prepare();

      expect(result, isA<AppError<VerifiedAsrModelBundle>>());
      expect(
        (result as AppError<VerifiedAsrModelBundle>).failure.code,
        'model_integrity',
      );
      expect(publishedBundle().existsSync(), isFalse);
      expect(stagingBundle().existsSync(), isFalse);
      await store.close();
    }
  });

  test(
    'suspension cancels loopback transport and suppresses stale publication',
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
      final states = <ModelStoreState<VerifiedAsrModelBundle>>[];
      final subscription = store.states.listen(states.add);
      addTearDown(subscription.cancel);

      final preparation = store.prepare();
      await firstChunkSent.future.timeout(const Duration(seconds: 5));
      await store.suspend().timeout(const Duration(seconds: 5));
      final result = await preparation;
      releaseResponse.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result, isA<AppError<VerifiedAsrModelBundle>>());
      expect(
        (result as AppError<VerifiedAsrModelBundle>).failure.code,
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
      expect(publishedBundle().existsSync(), isFalse);
    },
  );
}

Future<void> _respondWithBytes(HttpRequest request, Uint8List bytes) async {
  request.response.contentLength = bytes.length;
  request.response.add(bytes);
  await request.response.close();
}

final class _TinyAsrArchive {
  _TinyAsrArchive._({
    required this.files,
    required this.archiveBytes,
    required this.tarByteSize,
    required this.extractedByteSize,
    required this.treeSha256,
  });

  factory _TinyAsrArchive.create() {
    final files = <String, Uint8List>{
      modelFilename: Uint8List.fromList(
        List<int>.generate(113, (index) => (index * 29 + 11) % 256),
      ),
      tokensFilename: Uint8List.fromList(utf8.encode('<blk> 0\na 1\nb 2\n')),
      'README.md': Uint8List.fromList(utf8.encode('tiny deterministic ASR fixture')),
    };
    final archive = Archive()..add(ArchiveFile.directory('$rootName/'));
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
    return _TinyAsrArchive._(
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

  static const archiveFilename = 'tiny-asr.tar.bz2';
  static const rootName = 'tiny-streaming-asr';
  static const modelFilename = 'model.int8.onnx';
  static const tokensFilename = 'tokens.txt';

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
        // Client cancellation is expected in suspension scenarios.
      } on SocketException {
        // Client cancellation is expected in suspension scenarios.
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
      'http://${_server.address.host}:${_server.port}/'
      '${_TinyAsrArchive.archiveFilename}',
    );
  }

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

final class _GatedModelBundleVerifier implements ModelBundleVerifier {
  _GatedModelBundleVerifier(this._delegate);

  final ModelBundleVerifier _delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ModelBundleVerification> verify(String bundleDirectoryPath) async {
    started.complete();
    await release.future;
    return _delegate.verify(bundleDirectoryPath);
  }
}
