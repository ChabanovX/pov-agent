import 'dart:async';
import 'dart:io';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/mappers/model_store_failure_mapper.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';
import 'package:pov_agent/features/assistant/data/models/qwen_model_manifest.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Acquires and verifies one pinned Qwen artifact.
///
/// The store owns the download staging file and preparation lifecycle. The
/// Concurrent prepares share one attempt. Suspend invalidates that attempt
/// before cancelling transport, so stale progress, failure, or readiness can
/// never replace the suspended state. Native llama.cpp activation is a
/// foreground concern owned by the observer model session, not acquisition.
final class VerifiedQwenModelStore implements QwenModelStore, CacheVerifyingModelStore<VerifiedModelArtifact> {
  /// Creates a model store from explicit transport and storage policies.
  factory VerifiedQwenModelStore({
    required QwenModelManifest manifest,
    required ModelDirectoryProvider directoryProvider,
    required ModelDiskCapacityGateway diskCapacityGateway,
    required ModelArtifactDownloader downloader,
    required ModelChecksumVerifier checksumVerifier,
  }) {
    return VerifiedQwenModelStore._(
      manifest: manifest,
      directoryProvider: directoryProvider,
      diskCapacityGateway: diskCapacityGateway,
      downloader: downloader,
      checksumVerifier: checksumVerifier,
    );
  }

  VerifiedQwenModelStore._({
    required this._manifest,
    required this._directoryProvider,
    required this._diskCapacityGateway,
    required this._downloader,
    required this._checksumVerifier,
  });

  final QwenModelManifest _manifest;
  final ModelDirectoryProvider _directoryProvider;
  final ModelDiskCapacityGateway _diskCapacityGateway;
  final ModelArtifactDownloader _downloader;
  final ModelChecksumVerifier _checksumVerifier;

  final StreamController<QwenModelStoreState> _statesController = StreamController.broadcast(
    sync: true,
  );
  QwenModelStoreState _current = const QwenModelStoreState.idle();
  VerifiedModelArtifact? _verifiedArtifact;

  bool _isClosed = false;
  bool _isSuspended = false;
  int _preparationEpoch = 0;
  Future<AppResult<VerifiedModelArtifact>>? _activePreparation;
  Future<AppResult<bool>>? _activeCacheVerification;
  ModelDownloadCancellation? _activeDownloadCancellation;
  File? _activePartialFile;
  Future<void>? _activeSuspension;
  Future<void>? _closeTask;

  // ── ModelStore lifecycle ─────────────────────────────────────────

  @override
  QwenModelStoreState get current => _current;

  @override
  Stream<QwenModelStoreState> get states => _statesController.stream;

  @override
  Future<AppResult<VerifiedModelArtifact>> prepare() {
    if (_isClosed) {
      return Future.value(
        const AppError(
          UnexpectedFailure(
            code: 'model_store_closed',
            message: 'The model store is already closed.',
          ),
        ),
      );
    }

    final activeSuspension = _activeSuspension;
    if (activeSuspension != null) {
      return _prepareAfterSuspension(activeSuspension);
    }

    final activeCacheVerification = _activeCacheVerification;
    if (activeCacheVerification != null) {
      return _prepareAfterCacheVerification(activeCacheVerification);
    }

    final activePreparation = _activePreparation;
    if (activePreparation != null) return activePreparation;

    _isSuspended = false;
    final epoch = ++_preparationEpoch;
    final verifiedArtifact = _verifiedArtifact;
    if (verifiedArtifact != null) {
      _publishForEpoch(epoch, QwenModelStoreState.ready(verifiedArtifact));
      return Future.value(AppSuccess(verifiedArtifact));
    }
    final completer = Completer<AppResult<VerifiedModelArtifact>>();
    final preparation = completer.future;
    _activePreparation = preparation;
    unawaited(_completePreparation(epoch, completer, preparation));
    return preparation;
  }

  @override
  Future<AppResult<bool>> verifyCache() {
    if (_isClosed) {
      return Future.value(
        const AppError<bool>(
          UnexpectedFailure(
            code: 'model_store_closed',
            message: 'The model store is already closed.',
          ),
        ),
      );
    }

    final activeSuspension = _activeSuspension;
    if (activeSuspension != null) {
      return _verifyCacheAfterSuspension(activeSuspension);
    }

    final activeCacheVerification = _activeCacheVerification;
    if (activeCacheVerification != null) return activeCacheVerification;

    final activePreparation = _activePreparation;
    if (activePreparation != null) {
      return _verifyCacheAfterPreparation(activePreparation);
    }

    _isSuspended = false;
    final epoch = ++_preparationEpoch;
    late final Future<AppResult<bool>> task;
    task =
        Future<AppResult<bool>>.microtask(
          () => _verifyCacheForEpoch(epoch),
        ).whenComplete(() {
          if (identical(_activeCacheVerification, task)) {
            _activeCacheVerification = null;
          }
        });
    _activeCacheVerification = task;
    return task;
  }

  Future<AppResult<bool>> _verifyCacheForEpoch(int epoch) async {
    try {
      _publishForEpoch(epoch, const QwenModelStoreState.loading());
      final directory = await _directoryProvider.resolve();
      _ensureCurrentEpoch(epoch);
      final verifiedFile = File(
        '${directory.path}${Platform.pathSeparator}${_manifest.filename}',
      );
      final partialFile = File('${verifiedFile.path}.part');
      await _deleteIfPresent(partialFile);
      _ensureCurrentEpoch(epoch);

      // Cache probes originate on the UI isolate, so keep filesystem metadata
      // access asynchronous before checksum work moves to its isolate.
      // ignore: avoid_slow_async_io
      if (!await verifiedFile.exists()) {
        _verifiedArtifact = null;
        _publishForEpoch(epoch, const QwenModelStoreState.idle());
        return const AppSuccess(false);
      }
      if (!await _matchesManifest(verifiedFile, epoch)) {
        await verifiedFile.delete();
        _ensureCurrentEpoch(epoch);
        _verifiedArtifact = null;
        _publishForEpoch(epoch, const QwenModelStoreState.idle());
        return const AppSuccess(false);
      }

      _publishReady(_artifactFor(verifiedFile), epoch);
      return const AppSuccess(true);
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      final failure = _isCurrentEpoch(epoch)
          ? ModelStoreFailureMapper.map(error, stackTrace)
          : ModelStoreFailureMapper.map(
              const ModelPreparationCancelledException(),
              stackTrace,
            );
      if (_isCurrentEpoch(epoch)) {
        _publishForEpoch(epoch, QwenModelStoreState.failure(failure));
      }
      return AppError(failure);
    }
  }

  Future<AppResult<bool>> _verifyCacheAfterSuspension(
    Future<void> suspension,
  ) async {
    try {
      await suspension;
    } catch (error, stackTrace) {
      if (error is Error) rethrow;
      return AppError(ModelStoreFailureMapper.map(error, stackTrace));
    }
    return verifyCache();
  }

  Future<AppResult<bool>> _verifyCacheAfterPreparation(
    Future<AppResult<VerifiedModelArtifact>> preparation,
  ) async {
    final result = await preparation;
    return switch (result) {
      AppSuccess<VerifiedModelArtifact>() => const AppSuccess(true),
      AppError<VerifiedModelArtifact>(:final failure) => AppError(failure),
    };
  }

  Future<AppResult<VerifiedModelArtifact>> _prepareAfterCacheVerification(
    Future<AppResult<bool>> verification,
  ) async {
    await verification;
    return prepare();
  }

  @override
  Future<void> suspend() {
    if (_isClosed) {
      return _closeTask ?? Future.value();
    }
    final activeSuspension = _activeSuspension;
    if (activeSuspension != null) return activeSuspension;

    // Invalidation precedes every await so already-queued progress and load
    // completions observe suspension before they can publish.
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
    return _closeTask ??= _closeOnce();
  }

  // ── Lifecycle task completion ────────────────────────────────────

  Future<void> _completePreparation(
    int epoch,
    Completer<AppResult<VerifiedModelArtifact>> completer,
    Future<AppResult<VerifiedModelArtifact>> preparation,
  ) async {
    try {
      completer.complete(await _prepareForEpoch(epoch));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _clearCompletedPreparation(preparation);
    }
  }

  Future<AppResult<VerifiedModelArtifact>> _prepareAfterSuspension(
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

  // ── Artifact preparation ─────────────────────────────────────────

  Future<AppResult<VerifiedModelArtifact>> _prepareForEpoch(int epoch) async {
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
        _publishForEpoch(epoch, QwenModelStoreState.failure(failure));
      }
      return AppError(failure);
    }
  }

  Future<AppResult<VerifiedModelArtifact>> _performPreparation(int epoch) async {
    _publishForEpoch(epoch, const QwenModelStoreState.loading());
    final directory = await _directoryProvider.resolve();
    _ensureCurrentEpoch(epoch);
    await directory.create(recursive: true);
    _ensureCurrentEpoch(epoch);

    final verifiedFile = File(
      '${directory.path}${Platform.pathSeparator}${_manifest.filename}',
    );
    final partialFile = File('${verifiedFile.path}.part');
    _activePartialFile = partialFile;

    try {
      // Keep metadata I/O asynchronous because preparation starts on the UI isolate.
      // ignore: avoid_slow_async_io
      if (await verifiedFile.exists()) {
        final cacheMatches = await _matchesManifest(verifiedFile, epoch);
        if (cacheMatches) {
          await _deleteIfPresent(partialFile);
          return _publishReady(_artifactFor(verifiedFile), epoch);
        }
        await verifiedFile.delete();
        _ensureCurrentEpoch(epoch);
      }

      // A background URLSession publishes only complete bytes at this path.
      // Process termination can happen before Dart atomically promotes them,
      // so reconcile the staging file before asking transport to start again.
      // ignore: avoid_slow_async_io
      if (await partialFile.exists()) {
        if (await _matchesManifest(partialFile, epoch)) {
          final publishedFile = await partialFile.rename(verifiedFile.path);
          _ensureCurrentEpoch(epoch);
          return _publishReady(_artifactFor(publishedFile), epoch);
        }
        await partialFile.delete();
        _ensureCurrentEpoch(epoch);
      }

      await _requireDownloadCapacity(directory.path, epoch);
      await _downloadIntoPartialFile(partialFile, epoch);
      final partialMatches = await _matchesManifest(partialFile, epoch);
      if (!partialMatches) {
        throw const ModelIntegrityException(
          reason: 'downloaded bytes differ from the pinned size or SHA-256',
        );
      }
      _ensureCurrentEpoch(epoch);

      final publishedFile = await partialFile.rename(verifiedFile.path);
      _ensureCurrentEpoch(epoch);
      return _publishReady(_artifactFor(publishedFile), epoch);
    } finally {
      await _deleteIfPresent(partialFile);
      if (identical(_activePartialFile, partialFile)) {
        _activePartialFile = null;
      }
    }
  }

  Future<bool> _matchesManifest(File file, int epoch) async {
    _publishForEpoch(epoch, const QwenModelStoreState.verifying());
    final byteSize = await file.length();
    _ensureCurrentEpoch(epoch);
    if (byteSize != _manifest.byteSize) return false;

    final digest = await _checksumVerifier.sha256ForFile(file.path);
    _ensureCurrentEpoch(epoch);
    return digest == _manifest.sha256;
  }

  Future<void> _requireDownloadCapacity(String directoryPath, int epoch) async {
    final availableBytes = await _diskCapacityGateway.availableBytes(directoryPath);
    _ensureCurrentEpoch(epoch);
    final requiredBytes = _manifest.byteSize + _manifest.downloadReserveBytes;
    if (availableBytes < requiredBytes) {
      throw ModelInsufficientStorageException(
        requiredBytes: requiredBytes,
        availableBytes: availableBytes,
      );
    }
  }

  Future<void> _downloadIntoPartialFile(File partialFile, int epoch) async {
    final cancellation = ModelDownloadCancellation();
    _activeDownloadCancellation = cancellation;
    var lastPublishedProgress = 0.0;
    _publishForEpoch(epoch, const QwenModelStoreState.downloading(0));

    try {
      await _downloader.download(
        source: _manifest.downloadUri,
        destinationPath: partialFile.path,
        expectedBytes: _manifest.byteSize,
        cancellation: cancellation,
        onProgress: (receivedBytes) {
          if (!_isCurrentEpoch(epoch)) return;
          final progress = (receivedBytes / _manifest.byteSize).clamp(0.0, 1.0);
          if (progress <= lastPublishedProgress) return;
          lastPublishedProgress = progress;
          _publishForEpoch(epoch, QwenModelStoreState.downloading(progress));
        },
      );
      _ensureCurrentEpoch(epoch);
    } finally {
      if (identical(_activeDownloadCancellation, cancellation)) {
        _activeDownloadCancellation = null;
      }
    }
  }

  AppResult<VerifiedModelArtifact> _publishReady(
    VerifiedModelArtifact artifact,
    int epoch,
  ) {
    _verifiedArtifact = artifact;
    _publishForEpoch(epoch, QwenModelStoreState.ready(artifact));
    return AppSuccess(artifact);
  }

  VerifiedModelArtifact _artifactFor(File file) {
    return VerifiedModelArtifact(
      modelId: _manifest.modelId,
      revision: _manifest.revision,
      filePath: file.absolute.path,
      byteSize: _manifest.byteSize,
      sha256: _manifest.sha256,
    );
  }

  // ── Shutdown and stale-result gates ──────────────────────────────

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
    final cacheVerification = _activeCacheVerification;
    try {
      await Future.wait<void>([
        if (preparation != null) preparation.then<void>((_) {}),
        if (cacheVerification != null) cacheVerification.then<void>((_) {}),
      ]);
    } finally {
      if (preparation != null) {
        _clearCompletedPreparation(preparation);
      }
      if (identical(_activeCacheVerification, cacheVerification)) {
        _activeCacheVerification = null;
      }
      final partialFile = _activePartialFile;
      if (partialFile != null) await _deleteIfPresent(partialFile);
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    // Keep metadata I/O asynchronous because lifecycle calls originate on UI.
    // ignore: avoid_slow_async_io
    if (await file.exists()) await file.delete();
  }

  void _ensureCurrentEpoch(int epoch) {
    if (!_isCurrentEpoch(epoch)) {
      throw const ModelPreparationCancelledException();
    }
  }

  bool _isCurrentEpoch(int epoch) {
    return !_isClosed && !_isSuspended && epoch == _preparationEpoch;
  }

  void _publishForEpoch(int epoch, QwenModelStoreState state) {
    if (!_isCurrentEpoch(epoch)) return;
    _current = state;
    _statesController.add(state);
  }

  void _publishSuspended() {
    if (_isClosed) return;
    const state = QwenModelStoreState.suspended();
    _current = state;
    _statesController.add(state);
  }

  void _clearCompletedPreparation(
    Future<AppResult<VerifiedModelArtifact>> preparation,
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
