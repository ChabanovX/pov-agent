import 'dart:async';
import 'dart:io';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/mappers/model_store_failure_mapper.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';
import 'package:pov_agent/features/assistant/data/models/piper_model_manifest.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Downloads, extracts, and verifies one pinned Piper voice bundle.
///
/// The compressed archive and extracted tree are both verified before the
/// bundle is published. Concurrent prepares share one attempt. Suspension
/// invalidates progress before awaiting non-cancellable archive extraction, so
/// a late result can populate the cache but can never replace suspended state.
final class VerifiedPiperModelStore implements ModelStore<VerifiedPiperModelBundle> {
  /// Creates a store from explicit transport, storage, and archive policies.
  VerifiedPiperModelStore({
    required PiperModelManifest manifest,
    required ModelDirectoryProvider directoryProvider,
    required ModelDiskCapacityGateway diskCapacityGateway,
    required ModelArtifactDownloader downloader,
    required ModelChecksumVerifier checksumVerifier,
    required PiperBundleExtractor bundleExtractor,
    required PiperBundleVerifier bundleVerifier,
  }) : this._(
         manifest,
         directoryProvider,
         diskCapacityGateway,
         downloader,
         checksumVerifier,
         bundleExtractor,
         bundleVerifier,
       );

  VerifiedPiperModelStore._(
    this._manifest,
    this._directoryProvider,
    this._diskCapacityGateway,
    this._downloader,
    this._checksumVerifier,
    this._bundleExtractor,
    this._bundleVerifier,
  );

  final PiperModelManifest _manifest;
  final ModelDirectoryProvider _directoryProvider;
  final ModelDiskCapacityGateway _diskCapacityGateway;
  final ModelArtifactDownloader _downloader;
  final ModelChecksumVerifier _checksumVerifier;
  final PiperBundleExtractor _bundleExtractor;
  final PiperBundleVerifier _bundleVerifier;

  final StreamController<ModelStoreState<VerifiedPiperModelBundle>> _statesController = StreamController.broadcast(
    sync: true,
  );
  ModelStoreState<VerifiedPiperModelBundle> _current = const ModelStoreState.idle();

  VerifiedPiperModelBundle? _verifiedBundle;
  Future<AppResult<VerifiedPiperModelBundle>>? _activePreparation;
  Future<void>? _activeSuspension;
  Future<void>? _closeTask;
  ModelDownloadCancellation? _activeDownloadCancellation;
  File? _activePartialArchive;
  File? _activeExpandedArchive;
  Directory? _activeStagingDirectory;
  var _preparationEpoch = 0;
  var _isSuspended = false;
  var _isClosed = false;

  @override
  ModelStoreState<VerifiedPiperModelBundle> get current => _current;

  @override
  Stream<ModelStoreState<VerifiedPiperModelBundle>> get states => _statesController.stream;

  @override
  Future<AppResult<VerifiedPiperModelBundle>> prepare() {
    if (_isClosed) {
      return Future.value(
        const AppError(
          UnexpectedFailure(
            code: 'piper_model_store_closed',
            message: 'The Piper model store is already closed.',
          ),
        ),
      );
    }

    final activeSuspension = _activeSuspension;
    if (activeSuspension != null) {
      return _prepareAfterSuspension(activeSuspension);
    }
    final activePreparation = _activePreparation;
    if (activePreparation != null) return activePreparation;

    _isSuspended = false;
    final epoch = ++_preparationEpoch;
    final inMemoryBundle = _verifiedBundle;
    if (inMemoryBundle != null) {
      _publishForEpoch(epoch, ModelStoreState.ready(inMemoryBundle));
      return Future.value(AppSuccess(inMemoryBundle));
    }

    final completer = Completer<AppResult<VerifiedPiperModelBundle>>();
    final preparation = completer.future;
    _activePreparation = preparation;
    unawaited(_completePreparation(epoch, completer, preparation));
    return preparation;
  }

  @override
  Future<void> suspend() {
    if (_isClosed) return _closeTask ?? Future.value();
    final activeSuspension = _activeSuspension;
    if (activeSuspension != null) return activeSuspension;

    // Invalidate before any await so download, extraction, and verification
    // callbacks cannot publish over the suspended state.
    final completer = Completer<void>();
    final suspension = completer.future;
    _activeSuspension = suspension;
    _isSuspended = true;
    _preparationEpoch += 1;
    _activeDownloadCancellation?.cancel();
    _publishSuspended();
    unawaited(_completeSuspension(completer, suspension));
    return suspension;
  }

  @override
  Future<void> close() {
    final existing = _closeTask;
    if (existing != null) return existing;

    late final Future<void> task;
    task = _closeOnce().then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // Cleanup state remains owned after failure, so a later close must be
        // able to retry instead of receiving the same cached failed future.
        if (identical(_closeTask, task)) _closeTask = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _closeTask = task;
    return task;
  }

  Future<void> _completePreparation(
    int epoch,
    Completer<AppResult<VerifiedPiperModelBundle>> completer,
    Future<AppResult<VerifiedPiperModelBundle>> preparation,
  ) async {
    try {
      completer.complete(await _prepareForEpoch(epoch));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _clearCompletedPreparation(preparation);
    }
  }

  Future<AppResult<VerifiedPiperModelBundle>> _prepareAfterSuspension(
    Future<void> suspension,
  ) async {
    try {
      await suspension;
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(ModelStoreFailureMapper.map(error, stackTrace));
    }
    return prepare();
  }

  Future<void> _completeSuspension(
    Completer<void> completer,
    Future<void> suspension,
  ) async {
    try {
      await _stopPreparation();
      _clearCompletedSuspension(suspension);
      completer.complete();
    } catch (error, stackTrace) {
      _clearCompletedSuspension(suspension);
      completer.completeError(error, stackTrace);
    }
  }

  Future<AppResult<VerifiedPiperModelBundle>> _prepareForEpoch(
    int epoch,
  ) async {
    try {
      return await _performPreparation(epoch);
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      final failure = _isCurrentEpoch(epoch)
          ? ModelStoreFailureMapper.map(error, stackTrace)
          : ModelStoreFailureMapper.map(
              const ModelPreparationCancelledException(),
              stackTrace,
            );
      if (_isCurrentEpoch(epoch)) {
        _publishForEpoch(epoch, ModelStoreState.failure(failure));
      }
      return AppError(failure);
    }
  }

  Future<AppResult<VerifiedPiperModelBundle>> _performPreparation(
    int epoch,
  ) async {
    _publishForEpoch(epoch, const ModelStoreState.loading());
    final directory = await _directoryProvider.resolve();
    _ensureCurrentEpoch(epoch);
    await directory.create(recursive: true);
    _ensureCurrentEpoch(epoch);

    final archive = File(_childPath(directory.path, _manifest.archiveFilename));
    final partialArchive = File('${archive.path}.part');
    final bundleDirectory = Directory(
      _childPath(directory.path, _manifest.archiveRoot),
    );
    final stagingDirectory = Directory('${bundleDirectory.path}.extracting');
    final expandedArchive = File('${stagingDirectory.path}.tar');
    _activePartialArchive = partialArchive;
    _activeExpandedArchive = expandedArchive;
    _activeStagingDirectory = stagingDirectory;

    try {
      await _deleteFileIfPresent(partialArchive);
      await _deleteFileIfPresent(expandedArchive);
      await _deleteDirectoryIfPresent(stagingDirectory);
      _ensureCurrentEpoch(epoch);

      var archiveMatches = false;
      // Preparation begins on the UI isolate; avoid a synchronous disk probe
      // before checksum work moves to its background isolate.
      // ignore: avoid_slow_async_io
      if (await archive.exists()) {
        archiveMatches = await _matchesArchive(archive, epoch);
        if (!archiveMatches) {
          await archive.delete();
          await _deleteDirectoryIfPresent(bundleDirectory);
          _ensureCurrentEpoch(epoch);
        }
      }

      if (archiveMatches) {
        final cachedBundle = await _verifiedBundleIfPresent(
          bundleDirectory,
          epoch,
        );
        if (cachedBundle != null) return _publishReady(cachedBundle, epoch);
        await _requireCapacity(
          directory.path,
          _manifest.expandedArchiveByteSize + _manifest.extractedByteSize + _manifest.downloadReserveBytes,
          epoch,
        );
      } else {
        await _deleteDirectoryIfPresent(bundleDirectory);
        await _requireCapacity(
          directory.path,
          _manifest.archiveByteSize +
              _manifest.expandedArchiveByteSize +
              _manifest.extractedByteSize +
              _manifest.downloadReserveBytes,
          epoch,
        );
        await _downloadIntoPartialArchive(partialArchive, epoch);
        if (!await _matchesArchive(partialArchive, epoch)) {
          throw const ModelIntegrityException(
            reason: 'downloaded Piper bytes differ from the pinned archive',
          );
        }
        _ensureCurrentEpoch(epoch);
        await partialArchive.rename(archive.path);
        _ensureCurrentEpoch(epoch);
      }

      final bundle = await _extractAndVerify(
        archive: archive,
        bundleDirectory: bundleDirectory,
        stagingDirectory: stagingDirectory,
        expandedArchive: expandedArchive,
        epoch: epoch,
      );
      return _publishReady(bundle, epoch);
    } finally {
      await _deleteFileIfPresent(partialArchive);
      await _deleteFileIfPresent(expandedArchive);
      await _deleteDirectoryIfPresent(stagingDirectory);
      if (identical(_activePartialArchive, partialArchive)) {
        _activePartialArchive = null;
      }
      if (identical(_activeStagingDirectory, stagingDirectory)) {
        _activeStagingDirectory = null;
      }
      if (identical(_activeExpandedArchive, expandedArchive)) {
        _activeExpandedArchive = null;
      }
    }
  }

  Future<bool> _matchesArchive(File archive, int epoch) async {
    _publishForEpoch(epoch, const ModelStoreState.verifying());
    final byteSize = await archive.length();
    _ensureCurrentEpoch(epoch);
    if (byteSize != _manifest.archiveByteSize) return false;
    final digest = await _checksumVerifier.sha256ForFile(archive.path);
    _ensureCurrentEpoch(epoch);
    return digest == _manifest.archiveSha256;
  }

  Future<VerifiedPiperModelBundle?> _verifiedBundleIfPresent(
    Directory bundleDirectory,
    int epoch,
  ) async {
    // Cache discovery begins on the UI isolate, so keep this probe asynchronous.
    // ignore: avoid_slow_async_io
    if (!await bundleDirectory.exists()) return null;
    final bundle = await _verifyBundle(bundleDirectory, epoch);
    if (bundle != null) return bundle;
    await bundleDirectory.delete(recursive: true);
    _ensureCurrentEpoch(epoch);
    return null;
  }

  Future<VerifiedPiperModelBundle> _extractAndVerify({
    required File archive,
    required Directory bundleDirectory,
    required Directory stagingDirectory,
    required File expandedArchive,
    required int epoch,
  }) async {
    _publishForEpoch(epoch, const ModelStoreState.loading());
    await _bundleExtractor.extract(
      archivePath: archive.path,
      destinationPath: stagingDirectory.path,
      temporaryTarPath: expandedArchive.path,
      expectedTarByteSize: _manifest.expandedArchiveByteSize,
    );
    _ensureCurrentEpoch(epoch);
    final stagedBundle = Directory(
      _childPath(stagingDirectory.path, _manifest.archiveRoot),
    );
    final bundle = await _verifyBundle(stagedBundle, epoch);
    if (bundle == null) {
      throw const ModelIntegrityException(
        reason: 'the extracted Piper bundle differs from its pinned tree',
      );
    }
    await _deleteDirectoryIfPresent(bundleDirectory);
    final published = await stagedBundle.rename(bundleDirectory.path);
    _ensureCurrentEpoch(epoch);
    return _bundleFor(published);
  }

  Future<VerifiedPiperModelBundle?> _verifyBundle(
    Directory directory,
    int epoch,
  ) async {
    _publishForEpoch(epoch, const ModelStoreState.verifying());
    final verification = await _bundleVerifier.verify(directory.path);
    _ensureCurrentEpoch(epoch);
    if (verification.byteSize != _manifest.extractedByteSize ||
        verification.fileCount != _manifest.extractedFileCount ||
        verification.treeSha256 != _manifest.bundleTreeSha256) {
      return null;
    }

    final modelFile = File(_childPath(directory.path, _manifest.modelFilename));
    final tokensFile = File(_childPath(directory.path, _manifest.tokensFilename));
    final espeakDirectory = Directory(
      _childPath(directory.path, _manifest.espeakDataDirectory),
    );
    // Each path probe begins on the UI isolate, so asynchronous filesystem
    // calls preserve responsiveness while validating the published boundary.
    // ignore: avoid_slow_async_io
    final modelType = await FileSystemEntity.type(
      modelFile.path,
      followLinks: false,
    );
    // The token-table probe follows the same UI-isolate constraint.
    // ignore: avoid_slow_async_io
    final tokensType = await FileSystemEntity.type(
      tokensFile.path,
      followLinks: false,
    );
    // The eSpeak directory probe follows the same UI-isolate constraint.
    // ignore: avoid_slow_async_io
    final espeakType = await FileSystemEntity.type(
      espeakDirectory.path,
      followLinks: false,
    );
    _ensureCurrentEpoch(epoch);
    if (modelType != FileSystemEntityType.file ||
        tokensType != FileSystemEntityType.file ||
        espeakType != FileSystemEntityType.directory) {
      return null;
    }
    return _bundleFor(directory);
  }

  Future<void> _requireCapacity(
    String directoryPath,
    int requiredBytes,
    int epoch,
  ) async {
    final availableBytes = await _diskCapacityGateway.availableBytes(
      directoryPath,
    );
    _ensureCurrentEpoch(epoch);
    if (availableBytes < requiredBytes) {
      throw ModelInsufficientStorageException(
        requiredBytes: requiredBytes,
        availableBytes: availableBytes,
      );
    }
  }

  Future<void> _downloadIntoPartialArchive(File archive, int epoch) async {
    final cancellation = ModelDownloadCancellation();
    _activeDownloadCancellation = cancellation;
    var lastPublishedProgress = 0.0;
    _publishForEpoch(epoch, const ModelStoreState.downloading(0));
    try {
      await _downloader.download(
        source: _manifest.downloadUri,
        destinationPath: archive.path,
        expectedBytes: _manifest.archiveByteSize,
        cancellation: cancellation,
        onProgress: (receivedBytes) {
          if (!_isCurrentEpoch(epoch)) return;
          final progress = (receivedBytes / _manifest.archiveByteSize).clamp(
            0.0,
            1.0,
          );
          if (progress <= lastPublishedProgress) return;
          lastPublishedProgress = progress;
          _publishForEpoch(epoch, ModelStoreState.downloading(progress));
        },
      );
      _ensureCurrentEpoch(epoch);
    } finally {
      if (identical(_activeDownloadCancellation, cancellation)) {
        _activeDownloadCancellation = null;
      }
    }
  }

  AppResult<VerifiedPiperModelBundle> _publishReady(
    VerifiedPiperModelBundle bundle,
    int epoch,
  ) {
    _verifiedBundle = bundle;
    _publishForEpoch(epoch, ModelStoreState.ready(bundle));
    return AppSuccess(bundle);
  }

  VerifiedPiperModelBundle _bundleFor(Directory directory) {
    final absolutePath = directory.absolute.path;
    return VerifiedPiperModelBundle(
      modelId: _manifest.modelId,
      revision: _manifest.revision,
      bundleDirectoryPath: absolutePath,
      modelFilePath: _childPath(absolutePath, _manifest.modelFilename),
      tokensFilePath: _childPath(absolutePath, _manifest.tokensFilename),
      espeakDataDirectoryPath: _childPath(
        absolutePath,
        _manifest.espeakDataDirectory,
      ),
      extractedByteSize: _manifest.extractedByteSize,
      extractedFileCount: _manifest.extractedFileCount,
      bundleTreeSha256: _manifest.bundleTreeSha256,
    );
  }

  Future<void> _closeOnce() async {
    _isClosed = true;
    _isSuspended = true;
    _preparationEpoch += 1;
    _activeDownloadCancellation?.cancel();
    try {
      final suspension = _activeSuspension;
      if (suspension != null) await suspension;
      await _stopPreparation();
    } finally {
      await _statesController.close();
    }
  }

  Future<void> _stopPreparation() async {
    final preparation = _activePreparation;
    if (preparation != null) await preparation;
    final partialArchive = _activePartialArchive;
    if (partialArchive != null) await _deleteFileIfPresent(partialArchive);
    final expandedArchive = _activeExpandedArchive;
    if (expandedArchive != null) {
      await _deleteFileIfPresent(expandedArchive);
    }
    final stagingDirectory = _activeStagingDirectory;
    if (stagingDirectory != null) {
      await _deleteDirectoryIfPresent(stagingDirectory);
    }
  }

  Future<void> _deleteFileIfPresent(File file) async {
    // Cleanup can target model-sized staging resources from the UI isolate.
    // ignore: avoid_slow_async_io
    if (await file.exists()) await file.delete();
  }

  Future<void> _deleteDirectoryIfPresent(Directory directory) async {
    // Recursive staging cleanup must not synchronously walk hundreds of files.
    // ignore: avoid_slow_async_io
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void _ensureCurrentEpoch(int epoch) {
    if (!_isCurrentEpoch(epoch)) {
      throw const ModelPreparationCancelledException();
    }
  }

  bool _isCurrentEpoch(int epoch) {
    return !_isClosed && !_isSuspended && epoch == _preparationEpoch;
  }

  void _publishForEpoch(
    int epoch,
    ModelStoreState<VerifiedPiperModelBundle> state,
  ) {
    if (!_isCurrentEpoch(epoch)) return;
    _current = state;
    _statesController.add(state);
  }

  void _publishSuspended() {
    if (_isClosed) return;
    const state = ModelStoreState<VerifiedPiperModelBundle>.suspended();
    _current = state;
    _statesController.add(state);
  }

  void _clearCompletedPreparation(
    Future<AppResult<VerifiedPiperModelBundle>> preparation,
  ) {
    if (identical(_activePreparation, preparation)) {
      _activePreparation = null;
    }
  }

  void _clearCompletedSuspension(Future<void> suspension) {
    if (identical(_activeSuspension, suspension)) {
      _activeSuspension = null;
    }
  }
}

String _childPath(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}
