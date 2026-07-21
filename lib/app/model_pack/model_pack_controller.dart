import 'dart:async';

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

/// Reads free bytes from the volume that owns the model cache.
typedef ModelPackCapacityReader = Future<int> Function();

/// Coordinates the required model gate without acquiring camera or microphone.
///
/// Setup is single-flight: repeated check, install, and cancel requests join or
/// ignore the active operation. A monotonically increasing epoch invalidates
/// stale model completions before they can open the shell after cancellation.
/// A matching receipt is read before first-install storage policy and is trusted
/// only after Qwen, bundled Vision, Piper, and ASR caches verify in that order.
/// Otherwise installation preserves verified work and acquires the same four
/// dependencies sequentially after storage preflight. The controller owns its
/// state stream and store subscriptions, while composition closes the stores.
final class ModelPackController {
  /// Creates a controller from process-owned model stores and metadata.
  factory ModelPackController({
    required CacheVerifyingModelStore<VerifiedModelArtifact> qwenStore,
    required VisionModelVerifier visionVerifier,
    required CacheVerifyingModelStore<VerifiedPiperModelBundle> piperStore,
    required CacheVerifyingModelStore<VerifiedAsrModelBundle> asrStore,
    required ModelPackReceiptStore receiptStore,
    required ModelPackCapacityReader capacityReader,
    required String fingerprint,
    required int qwenDownloadBytes,
    required int piperDownloadBytes,
    required int asrDownloadBytes,
  }) {
    if (fingerprint.isEmpty) {
      throw ArgumentError.value(
        fingerprint,
        'fingerprint',
        'must not be empty',
      );
    }
    if (qwenDownloadBytes < 0 || piperDownloadBytes < 0 || asrDownloadBytes < 0) {
      throw ArgumentError('Model download sizes must not be negative.');
    }
    return ModelPackController._(
      qwenStore: qwenStore,
      visionVerifier: visionVerifier,
      piperStore: piperStore,
      asrStore: asrStore,
      receiptStore: receiptStore,
      capacityReader: capacityReader,
      fingerprint: fingerprint,
      qwenDownloadBytes: qwenDownloadBytes,
      piperDownloadBytes: piperDownloadBytes,
      asrDownloadBytes: asrDownloadBytes,
    );
  }

  ModelPackController._({
    required this._qwenStore,
    required this._visionVerifier,
    required this._piperStore,
    required this._asrStore,
    required this._receiptStore,
    required this._capacityReader,
    required this._fingerprint,
    required int qwenDownloadBytes,
    required int piperDownloadBytes,
    required int asrDownloadBytes,
  }) : _current = ModelPackState(
         phase: ModelPackPhase.checking,
         items: [
           ModelPackItemState(
             kind: ModelPackItemKind.assistant,
             technicalName: 'Qwen3-0.6B',
             downloadBytes: qwenDownloadBytes,
             phase: ModelPackItemPhase.waiting,
           ),
           const ModelPackItemState(
             kind: ModelPackItemKind.vision,
             technicalName: 'YOLO26n',
             downloadBytes: 0,
             phase: ModelPackItemPhase.waiting,
           ),
           ModelPackItemState(
             kind: ModelPackItemKind.voice,
             technicalName: 'Piper',
             downloadBytes: piperDownloadBytes,
             phase: ModelPackItemPhase.waiting,
           ),
           ModelPackItemState(
             kind: ModelPackItemKind.listening,
             technicalName: 'ASR',
             downloadBytes: asrDownloadBytes,
             phase: ModelPackItemPhase.waiting,
           ),
         ],
       ) {
    _subscriptions.addAll([
      _qwenStore.states.listen(
        (state) => _onStoreState(ModelPackItemKind.assistant, state),
      ),
      _piperStore.states.listen(
        (state) => _onStoreState(ModelPackItemKind.voice, state),
      ),
      _asrStore.states.listen(
        (state) => _onStoreState(ModelPackItemKind.listening, state),
      ),
    ]);
  }

  final CacheVerifyingModelStore<VerifiedModelArtifact> _qwenStore;
  final VisionModelVerifier _visionVerifier;
  final CacheVerifyingModelStore<VerifiedPiperModelBundle> _piperStore;
  final CacheVerifyingModelStore<VerifiedAsrModelBundle> _asrStore;
  final ModelPackReceiptStore _receiptStore;
  final ModelPackCapacityReader _capacityReader;
  final String _fingerprint;

  // ── Owned streams and operation slots ───────────────────────────

  final StreamController<ModelPackState> _states = StreamController<ModelPackState>.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];

  ModelPackState _current;
  Future<void>? _checkTask;
  Future<void>? _installationTask;
  Future<void>? _cancelTask;
  Future<void>? _closeTask;
  var _epoch = 0;
  var _closed = false;

  // ── Public lifecycle ────────────────────────────────────────────

  /// Latest setup state, synchronously available to the root router.
  ModelPackState get current => _current;

  /// Setup states in publication order.
  Stream<ModelPackState> get states => _states.stream;

  /// Validates a returning pack or performs first-install storage preflight.
  ///
  /// Concurrent calls share one check. A missing receipt never starts network
  /// work; the user must explicitly request [install].
  Future<void> start() {
    if (_closed || _current.phase == ModelPackPhase.complete) {
      return Future.value();
    }
    final activeCheck = _checkTask;
    if (activeCheck != null) return activeCheck;
    final activeCancellation = _cancelTask;
    if (activeCancellation != null) {
      return activeCancellation.then((_) => start());
    }
    final activeInstallation = _installationTask;
    if (activeInstallation != null) return activeInstallation;
    return _startCheckTask();
  }

  /// Installs remaining models in Qwen, Vision, Piper, then ASR order.
  ///
  /// Repeated requests while active join the first operation.
  Future<void> install() {
    if (_closed || _current.phase == ModelPackPhase.complete) {
      return Future.value();
    }
    final activeCancellation = _cancelTask;
    if (activeCancellation != null) {
      return activeCancellation.then((_) => install());
    }
    final activeInstallation = _installationTask;
    if (activeInstallation != null) return activeInstallation;
    final activeCheck = _checkTask;
    if (activeCheck != null) return activeCheck.then((_) => install());
    if (!_hasSuccessfulPreflight) return Future.value();
    return _startInstallationTask(++_epoch);
  }

  /// Stops active setup and preserves every verified artifact on disk.
  ///
  /// Repeated cancellation requests share one teardown operation.
  Future<void> cancel() {
    if (_closed) return Future.value();
    final activeCancellation = _cancelTask;
    if (activeCancellation != null) return activeCancellation;
    if (_installationTask == null) return Future.value();
    return _startCancelTask(++_epoch);
  }

  /// Rechecks storage after a preflight failure.
  Future<void> checkAgain() {
    if (_closed || _installationTask != null) return Future.value();
    return start();
  }

  bool get _hasSuccessfulPreflight {
    final availableBytes = _current.availableStorageBytes;
    return availableBytes != null &&
        availableBytes >= ModelPackState.requiredStorageBytes &&
        (_current.phase == ModelPackPhase.ready || _current.phase == ModelPackPhase.failure);
  }

  // ── Single-flight task ownership ────────────────────────────────

  Future<void> _startCheckTask() {
    final epoch = ++_epoch;
    late final Future<void> task;
    // Publish only after the slot is assigned so synchronous listeners can
    // safely join or cancel the operation they just observed.
    task = Future<void>.microtask(() => _runCheck(epoch)).whenComplete(() {
      if (identical(_checkTask, task)) _checkTask = null;
    });
    _checkTask = task;
    return task;
  }

  Future<void> _startInstallationTask(int epoch) {
    late final Future<void> task;
    task =
        Future<void>.microtask(
          () => _runInstallation(epoch),
        ).whenComplete(() {
          if (identical(_installationTask, task)) _installationTask = null;
        });
    _installationTask = task;
    return task;
  }

  Future<void> _startCancelTask(int epoch) {
    late final Future<void> task;
    task = Future<void>.microtask(() => _runCancel(epoch)).whenComplete(() {
      if (identical(_cancelTask, task)) _cancelTask = null;
    });
    _cancelTask = task;
    return task;
  }

  // ── Receipt and first-install preflight ─────────────────────────

  Future<void> _runCheck(int epoch) async {
    if (!_isCurrent(epoch)) return;
    _emit(
      _current.copyWith(
        phase: ModelPackPhase.checking,
        retainAvailableStorage: false,
      ),
    );

    String? receipt;
    try {
      receipt = await _receiptStore.read();
    } on Object catch (error, stackTrace) {
      _emitFailure(
        UnexpectedFailure(
          code: 'model_pack_receipt_read_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return;
    }
    if (!_isCurrent(epoch)) return;

    if (receipt == _fingerprint) {
      final cacheStatus = await _verifyCachedPack(epoch);
      if (!_isCurrent(epoch) || cacheStatus == _CachedPackStatus.failure) {
        return;
      }
      if (cacheStatus == _CachedPackStatus.complete) {
        _emit(_current.copyWith(phase: ModelPackPhase.complete));
        return;
      }

      try {
        await _receiptStore.clear();
      } on Object catch (error, stackTrace) {
        if (!_isCurrent(epoch)) return;
        _emitFailure(
          UnexpectedFailure(
            code: 'model_pack_receipt_clear_failed',
            message: error.toString(),
            cause: error,
            stackTrace: stackTrace,
          ),
        );
        return;
      }
      if (!_isCurrent(epoch)) return;
    }

    int availableBytes;
    try {
      availableBytes = await _capacityReader();
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(epoch)) return;
      _emitFailure(
        DeviceUnavailableFailure(
          code: 'model_pack_storage_unavailable',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return;
    }
    if (!_isCurrent(epoch)) return;
    if (availableBytes < ModelPackState.requiredStorageBytes) {
      _emit(
        _current.copyWith(
          phase: ModelPackPhase.failure,
          availableStorageBytes: availableBytes,
          retainAvailableStorage: false,
          failure: const DeviceUnavailableFailure(
            code: 'model_pack_insufficient_storage',
          ),
        ),
      );
      return;
    }

    _emit(
      _current.copyWith(
        phase: ModelPackPhase.ready,
        availableStorageBytes: availableBytes,
        retainAvailableStorage: false,
      ),
    );
  }

  Future<_CachedPackStatus> _verifyCachedPack(int epoch) async {
    var complete = true;
    final qwen = await _verifyCachedStore(
      epoch,
      ModelPackItemKind.assistant,
      _qwenStore,
    );
    if (qwen == _CacheItemStatus.failure) return _CachedPackStatus.failure;
    complete = qwen == _CacheItemStatus.verified;

    final vision = await _verifyVision(epoch, verifyAgain: true);
    if (!vision) return _CachedPackStatus.failure;

    final piper = await _verifyCachedStore(
      epoch,
      ModelPackItemKind.voice,
      _piperStore,
    );
    if (piper == _CacheItemStatus.failure) return _CachedPackStatus.failure;
    complete = complete && piper == _CacheItemStatus.verified;

    final asr = await _verifyCachedStore(
      epoch,
      ModelPackItemKind.listening,
      _asrStore,
    );
    if (asr == _CacheItemStatus.failure) return _CachedPackStatus.failure;
    complete = complete && asr == _CacheItemStatus.verified;
    return complete ? _CachedPackStatus.complete : _CachedPackStatus.incomplete;
  }

  // ── Ordered installation ────────────────────────────────────────

  Future<void> _runInstallation(int epoch) async {
    if (!_isCurrent(epoch)) return;
    _emit(_current.copyWith(phase: ModelPackPhase.installing));

    final qwenReady = await _prepare(
      epoch,
      ModelPackItemKind.assistant,
      _qwenStore,
    );
    if (!qwenReady) return;
    final visionReady = await _verifyVision(epoch);
    if (!visionReady) return;
    final piperReady = await _prepare(
      epoch,
      ModelPackItemKind.voice,
      _piperStore,
    );
    if (!piperReady) return;
    final asrReady = await _prepare(
      epoch,
      ModelPackItemKind.listening,
      _asrStore,
    );
    if (!asrReady || !_isCurrent(epoch)) return;

    try {
      await _receiptStore.write(_fingerprint);
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(epoch)) return;
      _emitFailure(
        UnexpectedFailure(
          code: 'model_pack_receipt_write_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return;
    }
    if (_isCurrent(epoch)) {
      _emit(_current.copyWith(phase: ModelPackPhase.complete));
    }
  }

  Future<_CacheItemStatus> _verifyCachedStore<TArtifact extends Object>(
    int epoch,
    ModelPackItemKind kind,
    CacheVerifyingModelStore<TArtifact> store,
  ) async {
    if (!_isCurrent(epoch)) return _CacheItemStatus.failure;
    _replaceItem(
      _current
          .item(kind)
          .withStatus(
            phase: ModelPackItemPhase.preparing,
          ),
    );
    AppResult<bool> result;
    try {
      result = await store.verifyCache();
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(epoch)) return _CacheItemStatus.failure;
      _markFailed(
        kind,
        UnexpectedFailure(
          code: 'model_pack_${kind.name}_cache_verification_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return _CacheItemStatus.failure;
    }
    if (!_isCurrent(epoch)) return _CacheItemStatus.failure;
    switch (result) {
      case AppSuccess<bool>(value: true):
        _markVerified(kind);
        return _CacheItemStatus.verified;
      case AppSuccess<bool>():
        return _markCacheMissing(kind);
      case AppError<bool>(:final failure):
        _markFailed(kind, failure);
        return _CacheItemStatus.failure;
    }
  }

  _CacheItemStatus _markCacheMissing(ModelPackItemKind kind) {
    _replaceItem(
      _current
          .item(kind)
          .withStatus(
            phase: ModelPackItemPhase.waiting,
          ),
    );
    return _CacheItemStatus.missing;
  }

  Future<bool> _verifyVision(
    int epoch, {
    bool verifyAgain = false,
  }) async {
    if (!_isCurrent(epoch)) return false;
    final item = _current.item(ModelPackItemKind.vision);
    if (!verifyAgain && item.phase == ModelPackItemPhase.verified) return true;
    _replaceItem(
      item.withStatus(phase: ModelPackItemPhase.verifying),
    );
    AppResult<VerifiedVisionModelArtifact> result;
    try {
      result = await _visionVerifier.verify();
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(epoch)) return false;
      return _markFailed(
        ModelPackItemKind.vision,
        UnexpectedFailure(
          code: 'model_pack_vision_verification_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_isCurrent(epoch)) return false;
    return switch (result) {
      AppSuccess<VerifiedVisionModelArtifact>() => _markVerified(ModelPackItemKind.vision),
      AppError<VerifiedVisionModelArtifact>(:final failure) => _markFailed(ModelPackItemKind.vision, failure),
    };
  }

  Future<bool> _prepare<TArtifact extends Object>(
    int epoch,
    ModelPackItemKind kind,
    ModelStore<TArtifact> store,
  ) async {
    if (!_isCurrent(epoch)) return false;
    final currentItem = _current.item(kind);
    if (currentItem.phase == ModelPackItemPhase.verified) return true;
    _replaceItem(
      currentItem.withStatus(phase: ModelPackItemPhase.preparing),
    );
    AppResult<TArtifact> result;
    try {
      result = await store.prepare();
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(epoch)) return false;
      return _markFailed(
        kind,
        UnexpectedFailure(
          code: 'model_pack_${kind.name}_prepare_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_isCurrent(epoch)) return false;
    return switch (result) {
      AppSuccess<TArtifact>() => _markVerified(kind),
      AppError<TArtifact>(:final failure) => _markFailed(kind, failure),
    };
  }

  // ── Cooperative cancellation ────────────────────────────────────

  Future<void> _runCancel(int epoch) async {
    if (!_isCurrent(epoch)) return;
    _emit(_current.copyWith(phase: ModelPackPhase.cancelling));
    try {
      await Future.wait<void>([
        _qwenStore.suspend(),
        _piperStore.suspend(),
        _asrStore.suspend(),
      ]);
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(epoch)) return;
      _emitFailure(
        UnexpectedFailure(
          code: 'model_pack_cancel_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return;
    }
    if (!_isCurrent(epoch)) return;
    _emit(
      _current.copyWith(
        phase: ModelPackPhase.ready,
        items: [
          for (final item in _current.items)
            if (item.phase == ModelPackItemPhase.verified) item else item.withStatus(phase: ModelPackItemPhase.waiting),
        ],
      ),
    );
  }

  // ── Store-state projection ──────────────────────────────────────

  void _onStoreState<TArtifact extends Object>(
    ModelPackItemKind kind,
    ModelStoreState<TArtifact> state,
  ) {
    if (_closed || _current.phase == ModelPackPhase.complete) return;
    final item = _current.item(kind);
    final replacement = switch (state.phase) {
      ModelStorePhase.idle => item.withStatus(
        phase: ModelPackItemPhase.waiting,
      ),
      ModelStorePhase.loading => item.withStatus(
        phase: ModelPackItemPhase.preparing,
      ),
      ModelStorePhase.downloading => item.withStatus(
        phase: ModelPackItemPhase.downloading,
        progress: state.downloadProgress,
      ),
      ModelStorePhase.verifying => item.withStatus(
        phase: ModelPackItemPhase.verifying,
      ),
      ModelStorePhase.ready => item.withStatus(
        phase: ModelPackItemPhase.verified,
      ),
      ModelStorePhase.failure => item.withStatus(
        phase: ModelPackItemPhase.failure,
        failure: state.failure,
      ),
      ModelStorePhase.suspended =>
        item.phase == ModelPackItemPhase.verified ? item : item.withStatus(phase: ModelPackItemPhase.waiting),
    };
    _replaceItem(replacement);
  }

  bool _markVerified(ModelPackItemKind kind) {
    _replaceItem(
      _current
          .item(kind)
          .withStatus(
            phase: ModelPackItemPhase.verified,
          ),
    );
    return true;
  }

  bool _markFailed(ModelPackItemKind kind, AppFailure failure) {
    _replaceItem(
      _current
          .item(kind)
          .withStatus(
            phase: ModelPackItemPhase.failure,
            failure: failure,
          ),
      phase: ModelPackPhase.failure,
      failure: failure,
    );
    return false;
  }

  void _replaceItem(
    ModelPackItemState replacement, {
    ModelPackPhase? phase,
    AppFailure? failure,
  }) {
    _emit(
      _current.replaceItem(
        replacement.kind,
        replacement,
        phase: phase,
        failure: failure,
        retainFailure: failure == null,
      ),
    );
  }

  void _emitFailure(AppFailure failure) {
    _emit(_current.copyWith(phase: ModelPackPhase.failure, failure: failure));
  }

  void _emit(ModelPackState state) {
    if (_closed) return;
    _current = state;
    _states.add(state);
  }

  bool _isCurrent(int epoch) => !_closed && epoch == _epoch;

  // ── Terminal teardown ───────────────────────────────────────────

  /// Stops publication and detaches from stores without closing injected ports.
  Future<void> close() {
    return _closeTask ??= _closeOnce();
  }

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    _epoch += 1;
    await Future.wait<void>([
      for (final subscription in _subscriptions) subscription.cancel(),
    ]);
    await _states.close();
  }
}

enum _CachedPackStatus { complete, incomplete, failure }

enum _CacheItemStatus { verified, missing, failure }
