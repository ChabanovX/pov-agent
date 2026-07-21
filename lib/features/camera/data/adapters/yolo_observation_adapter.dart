import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pov_agent/core/design_system/tokens/tokens.dart';
import 'package:pov_agent/features/camera/application/models/observation_configuration.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/ports/camera_permission_gateway.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/data/mappers/yolo_failure_mapper.dart';
import 'package:pov_agent/features/camera/data/mappers/yolo_result_mapper.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Adapts the live YOLO plugin to one [ObservationController] session.
///
/// Owns camera permission revalidation, the plugin view controller, model
/// download progress, surface revision invalidation, and the observation event
/// stream. App composition exposes its surface-facing state and callbacks to
/// presentation; raw plugin values remain inside the data boundary.
///
/// Lifecycle:
/// - [init] requests initial permission and starts model-progress observation.
/// - [enable] revalidates permission, records lens and power demand, and
///   reconciles an attached native view.
/// - [disable] pauses the attached native view without unloading the model.
/// - [retryModel] stops the controller and advances the surface revision.
/// - [close] invalidates callbacks before cancelling and disposing every owned
///   native and Dart resource.
///
/// The application coordinator serializes lifecycle commands. Native model
/// attachment, results, diagnostics, and failures are revision-gated. Close
/// invalidates pending reconciliation polls before their next controller
/// access.
final class YoloObservationAdapter implements ObservationController {
  /// Creates an adapter around the live YOLO platform surface.
  YoloObservationAdapter({
    required this._cameraPermissionGateway,
    this.configuration = ObservationConfiguration.milestoneOne,
  });

  /// The model and inference configuration used by this adapter.
  final ObservationConfiguration configuration;
  final CameraPermissionGateway _cameraPermissionGateway;
  final YOLOViewController _viewController = YOLOViewController();
  final StreamController<ObservationEvent> _eventsController = StreamController<ObservationEvent>.broadcast();
  final ValueNotifier<int> _surfaceRevision = ValueNotifier(0);

  StreamSubscription<DownloadProgress>? _downloadSubscription;
  CameraLens _desiredLens = CameraLens.back;
  CameraLens? _attachedLens;
  bool _requestedEnabled = false;
  bool _initialized = false;
  bool _closed = false;
  int _observationRevision = 0;
  int? _activeObservationRevision;
  int? _lensSwitchRevision;

  @override
  Stream<ObservationEvent> get events => _eventsController.stream;

  /// A revision that changes whenever the native surface must be recreated.
  ValueListenable<int> get surfaceRevision => _surfaceRevision;

  /// The lens that the next native surface should attach.
  CameraLens get desiredLens => _desiredLens;

  /// The controller bound to the current native YOLO surface.
  YOLOViewController get viewController => _viewController;

  @override
  Future<AppResult<CameraCapabilities>> init() async {
    if (_closed) {
      return const AppError(
        DeviceUnavailableFailure(
          code: 'observation_closed',
        ),
      );
    }
    if (!_initialized) {
      final permissionResult = await _cameraPermissionGateway.request();
      if (_closed) return _closedResult();
      if (permissionResult case AppError<void>(:final failure)) {
        return AppError<CameraCapabilities>(failure);
      }
      _initialized = true;
      _eventsController.add(const ObservationModelPreparing());
      // The package only exports DownloadProgress, so the pinned 0.6.10
      // manager stream is wrapped here and never leaks beyond this adapter.
      _downloadSubscription = YOLOModelManager.downloadProgress.listen(
        _handleDownloadProgress,
      );
    }

    // Milestone 1 targets iPhone 11, whose supported product lenses are fixed.
    // Native lens switching remains owned by YOLOViewController.
    return AppSuccess(
      CameraCapabilities(
        availableLenses: const [CameraLens.back, CameraLens.front],
        preferredLens: CameraLens.back,
      ),
    );
  }

  @override
  Future<AppResult<void>> enable(CameraLens lens) async {
    if (_closed) return _closedResult();

    // Camera permission can be revoked in Settings while the app is paused.
    // Revalidate before every native resume so the UI can recover explicitly.
    final permissionResult = await _cameraPermissionGateway.request();
    if (_closed) return _closedResult();
    if (permissionResult case AppError<void>(:final failure)) {
      return AppError<void>(failure);
    }

    final lensChanged = _desiredLens != lens;
    _desiredLens = lens;
    _requestedEnabled = true;

    final revision = lensChanged ? _invalidateObservationSource() : _observationRevision;

    if (_viewController.isInitialized) {
      if (_attachedLens != lens) {
        if (!await _switchAttachedLens(revision, lens)) {
          return _closedResult();
        }
      }
      await _viewController.resume();
    }
    if (_closed || revision != _observationRevision) {
      return _closedResult();
    }
    // Rebuild only after native switching/resume settles. The old surface is
    // already callback-invalidated, so it cannot publish frames in the gap.
    _publishSurfaceRevision(revision);
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> disable() async {
    if (_closed) return _closedResult();
    _requestedEnabled = false;
    if (_viewController.isInitialized) {
      await _viewController.pause();
    }
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryModel() async {
    if (_closed) return _closedResult();
    _eventsController.add(const ObservationModelPreparing());
    _attachedLens = null;
    // Invalidate callbacks before awaiting native stop, but delay rebuilding
    // the surface so a replacement view cannot attach to the controller that
    // is still being stopped.
    final revision = _invalidateObservationCallbacks();
    if (_viewController.isInitialized) {
      await _viewController.stop();
    }
    if (_closed || revision != _observationRevision) {
      return _closedResult();
    }
    _publishSurfaceRevision(revision);
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryObservation() => retryModel();

  /// Accepts a successful model callback from the current surface [revision].
  ///
  /// Callbacks from stale surfaces or a different [modelPath] are ignored.
  void handleModelLoaded({
    required int revision,
    required CameraLens attachedLens,
    required String modelPath,
  }) {
    if (_closed || revision != _observationRevision || modelPath != configuration.modelPath) {
      return;
    }
    _attachedLens = attachedLens;
    if (_lensSwitchRevision != revision) {
      _activeObservationRevision = revision;
    }
    _eventsController.add(const ObservationModelReady());
    unawaited(_reconcileAfterPlatformAttachment(revision));
  }

  /// Converts a native model [error] into an observation failure event.
  void handleModelError({
    required int revision,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (_closed || revision != _observationRevision) return;
    _activeObservationRevision = null;
    _eventsController.add(
      ObservationFailed(YoloFailureMapper.map(error, stackTrace)),
    );
  }

  /// Publishes domain detections mapped from current-surface [results].
  void handleResults({
    required int revision,
    required List<YOLOResult> results,
  }) {
    if (!_canPublishObservationCallback(revision)) return;
    final detections = YoloResultMapper.detectionsFromRaw(
      results.map((result) => result.toMap()),
    );
    _eventsController.add(
      ObservationDetectionsUpdated(
        detections: detections,
        observedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Publishes domain diagnostics mapped from current-surface [performance].
  void handlePerformance({
    required int revision,
    required YOLOPerformanceMetrics performance,
  }) {
    if (!_canPublishObservationCallback(revision)) return;
    _eventsController.add(
      ObservationDiagnosticsUpdated(
        YoloResultMapper.diagnosticsFromRaw(
          performance.toMap(),
          sampledAt: DateTime.now().toUtc(),
        ),
      ),
    );
  }

  int _invalidateObservationSource() {
    _eventsController.add(const ObservationSourceDiscontinuity());
    return _invalidateObservationCallbacks();
  }

  int _invalidateObservationCallbacks() {
    _activeObservationRevision = null;
    return _observationRevision += 1;
  }

  void _publishSurfaceRevision(int revision) {
    if (_surfaceRevision.value != revision) {
      _surfaceRevision.value = revision;
    }
  }

  bool _canPublishObservationCallback(int revision) {
    return !_closed && _requestedEnabled && revision == _observationRevision && revision == _activeObservationRevision;
  }

  Future<bool> _switchAttachedLens(
    int revision,
    CameraLens lens,
  ) async {
    _activeObservationRevision = null;
    _lensSwitchRevision = revision;
    try {
      await _viewController.switchCamera();
      if (_closed || revision != _observationRevision) return false;
      _attachedLens = lens;
      _activeObservationRevision = revision;
      return true;
    } finally {
      if (_lensSwitchRevision == revision) {
        _lensSwitchRevision = null;
      }
    }
  }

  void _handleDownloadProgress(DownloadProgress progress) {
    if (_closed || progress.modelId != configuration.modelPath) return;
    _eventsController.add(
      ObservationModelDownloadProgressed(progress.fraction),
    );
  }

  Future<void> _reconcileAfterPlatformAttachment(int revision) async {
    // YOLOView reports model resolution before its platform controller attaches.
    // Poll briefly so a tab/background pause requested during download cannot
    // let the newly-created native camera session run while the surface is hidden.
    for (var attempt = 0; attempt < _platformAttachmentAttempts; attempt += 1) {
      if (_closed || revision != _observationRevision) return;
      if (_viewController.isInitialized) {
        if (!_requestedEnabled) {
          await _viewController.pause();
        } else if (_attachedLens != _desiredLens) {
          if (!await _switchAttachedLens(revision, _desiredLens)) return;
        }
        // A newly attached YOLOView starts itself only after committing its
        // AVCaptureSession configuration. A redundant resume here can race
        // that setup and make iOS call startRunning inside the configuration
        // window. Later foreground and user resumes still enter through enable.
        return;
      }
      await Future<void>.delayed(AppAnimations.regular.fast);
    }
  }

  AppResult<T> _closedResult<T>() {
    return AppError<T>(
      const DeviceUnavailableFailure(
        code: 'observation_closed',
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Registration happens before the resolver starts DNS/HTTP work. Always
    // cancel, then clear only the no-active-download marker so a later app
    // runtime cannot inherit a stale cancellation.
    YOLOModelManager.cancelDownload(configuration.modelPath);
    YOLOModelManager.clearDownloadCancellation(configuration.modelPath);
    await _downloadSubscription?.cancel();
    await _viewController.stop();
    _viewController.dispose();
    _surfaceRevision.dispose();
    await _eventsController.close();
  }
}

const _platformAttachmentAttempts = 42;
