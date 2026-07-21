import 'dart:async';
import 'dart:io';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_model_artifact.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
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

/// Acquires, verifies, and activates one pinned Qwen artifact.
///
/// The store owns the download staging file and preparation lifecycle. The
/// injected [CommentGenerator] retains ownership of native model resources.
/// Concurrent prepares share one attempt. Suspend invalidates that attempt
/// before cancelling transport and native work, so stale progress, failure, or
/// readiness can never replace the suspended state. Prepares requested during
/// suspension wait until transport and native cleanup have both settled.
final class VerifiedQwenModelStore implements QwenModelStore {
  /// Creates a model store from explicit transport and storage policies.
  factory VerifiedQwenModelStore({
    required QwenModelManifest manifest,
    required ModelDirectoryProvider directoryProvider,
    required ModelDiskCapacityGateway diskCapacityGateway,
    required ModelArtifactDownloader downloader,
    required ModelChecksumVerifier checksumVerifier,
    required CommentGenerator commentGenerator,
  }) {
    return VerifiedQwenModelStore._(
      manifest: manifest,
      directoryProvider: directoryProvider,
      diskCapacityGateway: diskCapacityGateway,
      downloader: downloader,
      checksumVerifier: checksumVerifier,
      commentGenerator: commentGenerator,
    );
  }

  VerifiedQwenModelStore._({
    required this._manifest,
    required this._directoryProvider,
    required this._diskCapacityGateway,
    required this._downloader,
    required this._checksumVerifier,
    required this._commentGenerator,
  });

  final QwenModelManifest _manifest;
  final ModelDirectoryProvider _directoryProvider;
  final ModelDiskCapacityGateway _diskCapacityGateway;
  final ModelArtifactDownloader _downloader;
  final ModelChecksumVerifier _checksumVerifier;
  final CommentGenerator _commentGenerator;

  final StreamController<QwenModelStoreState> _statesController = StreamController.broadcast(
    sync: true,
  );
  QwenModelStoreState _current = const QwenModelStoreState.idle();

  bool _isClosed = false;
  bool _isSuspended = false;
  int _preparationEpoch = 0;
  Future<AppResult<VerifiedModelArtifact>>? _activePreparation;
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

    final activePreparation = _activePreparation;
    if (activePreparation != null) return activePreparation;

    _isSuspended = false;
    final epoch = ++_preparationEpoch;
    final completer = Completer<AppResult<VerifiedModelArtifact>>();
    final preparation = completer.future;
    _activePreparation = preparation;
    unawaited(_completePreparation(epoch, completer, preparation));
    return preparation;
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
      await _stopPreparationAndUnload();
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
      await _deleteIfPresent(partialFile);
      _ensureCurrentEpoch(epoch);

      // Keep metadata I/O asynchronous because preparation starts on the UI isolate.
      // ignore: avoid_slow_async_io
      if (await verifiedFile.exists()) {
        final cacheMatches = await _matchesManifest(verifiedFile, epoch);
        if (cacheMatches) {
          return await _loadVerifiedArtifact(
            _artifactFor(verifiedFile),
            epoch,
          );
        }
        await verifiedFile.delete();
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
      return await _loadVerifiedArtifact(
        _artifactFor(publishedFile),
        epoch,
      );
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

  Future<AppResult<VerifiedModelArtifact>> _loadVerifiedArtifact(
    VerifiedModelArtifact artifact,
    int epoch,
  ) async {
    _publishForEpoch(epoch, const QwenModelStoreState.loading());
    final loadResult = await _commentGenerator.loadModel(artifact);
    _ensureCurrentEpoch(epoch);
    return switch (loadResult) {
      AppSuccess<void>() => _publishReady(artifact, epoch),
      AppError<void>(:final failure) => _publishGeneratorFailure(failure, epoch),
    };
  }

  AppResult<VerifiedModelArtifact> _publishReady(
    VerifiedModelArtifact artifact,
    int epoch,
  ) {
    _publishForEpoch(epoch, QwenModelStoreState.ready(artifact));
    return AppSuccess(artifact);
  }

  AppResult<VerifiedModelArtifact> _publishGeneratorFailure(
    AppFailure failure,
    int epoch,
  ) {
    _publishForEpoch(epoch, QwenModelStoreState.failure(failure));
    return AppError(failure);
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
      await _stopPreparationAndUnload();
    } finally {
      await _statesController.close();
    }
  }

  Future<void> _stopPreparationAndUnload() async {
    final preparation = _activePreparation;
    try {
      await Future.wait<void>([
        _commentGenerator.unload(),
        if (preparation != null) preparation.then<void>((_) {}),
      ]);
    } finally {
      if (preparation != null) {
        _clearCompletedPreparation(preparation);
      }
      // A load may have crossed the first unload call before observing the
      // invalidated epoch. The second idempotent unload closes that race.
      await _commentGenerator.unload();
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
