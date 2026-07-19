import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

/// An adapter that owns the live YOLO surface and maps its plugin values.
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

    final lensChangedBeforeAttachment = _desiredLens != lens && !_viewController.isInitialized;
    _desiredLens = lens;
    _requestedEnabled = true;

    if (lensChangedBeforeAttachment) {
      _surfaceRevision.value += 1;
    }

    if (_viewController.isInitialized) {
      if (_attachedLens != lens) {
        await _viewController.switchCamera();
        _attachedLens = lens;
      }
      await _viewController.resume();
    }
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
    if (_viewController.isInitialized) {
      await _viewController.stop();
    }
    _attachedLens = null;
    _surfaceRevision.value += 1;
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
    if (_closed || revision != _surfaceRevision.value || modelPath != configuration.modelPath) {
      return;
    }
    _attachedLens = attachedLens;
    _eventsController.add(const ObservationModelReady());
    unawaited(_reconcileAfterPlatformAttachment(revision));
  }

  /// Converts a native model [error] into an observation failure event.
  void handleModelError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _eventsController.add(
      ObservationFailed(YoloFailureMapper.map(error, stackTrace)),
    );
  }

  /// Publishes domain detections mapped from native [results].
  void handleResults(List<YOLOResult> results) {
    if (_closed) return;
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

  /// Publishes domain diagnostics mapped from native [metrics].
  void handlePerformance(YOLOPerformanceMetrics metrics) {
    if (_closed) return;
    _eventsController.add(
      ObservationDiagnosticsUpdated(
        YoloResultMapper.diagnosticsFromRaw(
          metrics.toMap(),
          sampledAt: DateTime.now().toUtc(),
        ),
      ),
    );
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
      if (_closed || revision != _surfaceRevision.value) return;
      if (_viewController.isInitialized) {
        if (!_requestedEnabled) {
          await _viewController.pause();
        } else if (_attachedLens != _desiredLens) {
          await _viewController.switchCamera();
          _attachedLens = _desiredLens;
        } else {
          await _viewController.resume();
        }
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

/// Application-level platform surface over the native [YOLOView].
final class ObservationSurface extends StatelessWidget {
  /// Creates a native observation surface backed by [adapter].
  const ObservationSurface({
    required this.adapter,
    super.key,
  });

  /// The adapter that owns this surface's native controller and callbacks.
  final YoloObservationAdapter adapter;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: adapter.surfaceRevision,
      builder: (context, revision, _) {
        final attachedLens = adapter.desiredLens;
        final configuration = adapter.configuration;
        return YOLOView(
          key: ValueKey(('yolo-observation-surface', revision)),
          modelPath: configuration.modelPath,
          task: YOLOTask.detect,
          controller: adapter.viewController,
          cameraResolution: configuration.cameraResolution,
          confidenceThreshold: configuration.confidenceThreshold,
          iouThreshold: configuration.iouThreshold,
          useGpu: configuration.useGpu,
          lensFacing: switch (attachedLens) {
            CameraLens.back => LensFacing.back,
            CameraLens.front => LensFacing.front,
          },
          onResult: adapter.handleResults,
          onPerformanceMetrics: adapter.handlePerformance,
          onModelLoad: (modelPath, _) {
            adapter.handleModelLoaded(
              revision: revision,
              attachedLens: attachedLens,
              modelPath: modelPath,
            );
          },
          onModelError: (error, _, _) {
            adapter.handleModelError(error, StackTrace.current);
          },
        );
      },
    );
  }
}
