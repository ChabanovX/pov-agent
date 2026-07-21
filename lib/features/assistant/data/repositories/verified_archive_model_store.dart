import 'dart:async';
import 'dart:io';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/mappers/model_store_failure_mapper.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';
import 'package:pov_agent/features/assistant/data/models/verified_archive_model_manifest.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Filesystem kind required at one published model-bundle path.
enum ModelBundleEntryKind {
  /// A regular file that must exist without following links.
  file,

  /// A directory that must exist without following links.
  directory,
}

/// One runtime-critical path required inside a verified model bundle.
final class ModelBundleEntryRequirement {
  /// Creates a required regular file.
  factory ModelBundleEntryRequirement.file(String filename) {
    return ModelBundleEntryRequirement._(filename, ModelBundleEntryKind.file);
  }

  /// Creates a required directory.
  factory ModelBundleEntryRequirement.directory(String directoryName) {
    return ModelBundleEntryRequirement._(
      directoryName,
      ModelBundleEntryKind.directory,
    );
  }

  ModelBundleEntryRequirement._(this.pathComponent, this.kind) {
    VerifiedArchiveManifestValidation.pathComponent(
      pathComponent,
      name: 'pathComponent',
      label: 'A required model-bundle entry',
    );
  }

  /// Safe path component relative to the published bundle root.
  final String pathComponent;

  /// Filesystem entity kind required at [pathComponent].
  final ModelBundleEntryKind kind;
}

/// Projects one verified bundle directory into its application artifact.
typedef VerifiedArchiveArtifactFactory<TArtifact extends Object> =
    TArtifact Function(String absoluteBundleDirectoryPath);

/// Downloads, extracts, verifies, and atomically publishes a pinned model bundle.
///
/// The compressed archive and extracted tree are both verified before the
/// bundle is published. Concurrent prepares share one attempt. Suspension
/// invalidates progress before awaiting non-cancellable archive extraction, so
/// a late result can populate the cache but can never replace suspended state.
/// Typed stores supply only their runtime-critical entries and artifact
/// projection; this class retains complete lifecycle and staging ownership.
final class VerifiedArchiveModelStore<TArtifact extends Object> implements ModelStore<TArtifact> {
  /// Creates a store from explicit transport, storage, and archive policies.
  VerifiedArchiveModelStore({
    required VerifiedArchiveModelManifest manifest,
    required ModelDirectoryProvider directoryProvider,
    required ModelDiskCapacityGateway diskCapacityGateway,
    required ModelArtifactDownloader downloader,
    required ModelChecksumVerifier checksumVerifier,
    required ModelBundleExtractor bundleExtractor,
    required ModelBundleVerifier bundleVerifier,
    required List<ModelBundleEntryRequirement> requiredEntries,
    required VerifiedArchiveArtifactFactory<TArtifact> artifactFactory,
    required String closedFailureCode,
    required String closedFailureMessage,
  }) : this._(
         manifest,
         directoryProvider,
         diskCapacityGateway,
         downloader,
         checksumVerifier,
         bundleExtractor,
         bundleVerifier,
         List.unmodifiable(requiredEntries),
         artifactFactory,
         closedFailureCode,
         closedFailureMessage,
       );

  VerifiedArchiveModelStore._(
    this._manifest,
    this._directoryProvider,
    this._diskCapacityGateway,
    this._downloader,
    this._checksumVerifier,
    this._bundleExtractor,
    this._bundleVerifier,
    this._requiredEntries,
    this._artifactFactory,
    this._closedFailureCode,
    this._closedFailureMessage,
  ) : assert(_requiredEntries.isNotEmpty, 'At least one runtime entry is required.'),
      assert(_closedFailureCode.isNotEmpty, 'closedFailureCode must not be empty.'),
      assert(_closedFailureMessage.isNotEmpty, 'closedFailureMessage must not be empty.');

  final VerifiedArchiveModelManifest _manifest;
  final ModelDirectoryProvider _directoryProvider;
  final ModelDiskCapacityGateway _diskCapacityGateway;
  final ModelArtifactDownloader _downloader;
  final ModelChecksumVerifier _checksumVerifier;
  final ModelBundleExtractor _bundleExtractor;
  final ModelBundleVerifier _bundleVerifier;
  final List<ModelBundleEntryRequirement> _requiredEntries;
  final VerifiedArchiveArtifactFactory<TArtifact> _artifactFactory;
  final String _closedFailureCode;
  final String _closedFailureMessage;

  final StreamController<ModelStoreState<TArtifact>> _statesController = StreamController.broadcast(
    sync: true,
  );
  ModelStoreState<TArtifact> _current = const ModelStoreState.idle();

  TArtifact? _verifiedBundle;
  Future<AppResult<TArtifact>>? _activePreparation;
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
  ModelStoreState<TArtifact> get current => _current;

  @override
  Stream<ModelStoreState<TArtifact>> get states => _statesController.stream;

  @override
  Future<AppResult<TArtifact>> prepare() {
    if (_isClosed) {
      return Future.value(
        AppError(
          UnexpectedFailure(
            code: _closedFailureCode,
            message: _closedFailureMessage,
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

    final completer = Completer<AppResult<TArtifact>>();
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
    Completer<AppResult<TArtifact>> completer,
    Future<AppResult<TArtifact>> preparation,
  ) async {
    try {
      completer.complete(await _prepareForEpoch(epoch));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _clearCompletedPreparation(preparation);
    }
  }

  Future<AppResult<TArtifact>> _prepareAfterSuspension(
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

  Future<AppResult<TArtifact>> _prepareForEpoch(
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

  Future<AppResult<TArtifact>> _performPreparation(
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
            reason: 'downloaded model bytes differ from the pinned archive',
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

  Future<TArtifact?> _verifiedBundleIfPresent(
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

  Future<TArtifact> _extractAndVerify({
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
        reason: 'the extracted model bundle differs from its pinned tree',
      );
    }
    await _deleteDirectoryIfPresent(bundleDirectory);
    final published = await stagedBundle.rename(bundleDirectory.path);
    _ensureCurrentEpoch(epoch);
    return _bundleFor(published);
  }

  Future<TArtifact?> _verifyBundle(
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

    for (final requirement in _requiredEntries) {
      // Runtime entry probes begin on the UI isolate, so asynchronous
      // filesystem calls preserve responsiveness at the publication boundary.
      // ignore: avoid_slow_async_io
      final actualType = await FileSystemEntity.type(
        _childPath(directory.path, requirement.pathComponent),
        followLinks: false,
      );
      _ensureCurrentEpoch(epoch);
      final expectedType = switch (requirement.kind) {
        ModelBundleEntryKind.file => FileSystemEntityType.file,
        ModelBundleEntryKind.directory => FileSystemEntityType.directory,
      };
      if (actualType != expectedType) return null;
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

  AppResult<TArtifact> _publishReady(
    TArtifact bundle,
    int epoch,
  ) {
    _verifiedBundle = bundle;
    _publishForEpoch(epoch, ModelStoreState.ready(bundle));
    return AppSuccess(bundle);
  }

  TArtifact _bundleFor(Directory directory) {
    return _artifactFactory(directory.absolute.path);
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
    ModelStoreState<TArtifact> state,
  ) {
    if (!_isCurrentEpoch(epoch)) return;
    _current = state;
    _statesController.add(state);
  }

  void _publishSuspended() {
    if (_isClosed) return;
    final state = ModelStoreState<TArtifact>.suspended();
    _current = state;
    _statesController.add(state);
  }

  void _clearCompletedPreparation(
    Future<AppResult<TArtifact>> preparation,
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
