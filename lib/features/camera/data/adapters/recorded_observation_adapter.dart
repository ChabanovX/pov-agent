import 'dart:async';

import 'package:meta/meta.dart';
import 'package:pov_agent/features/camera/application/models/observation_configuration.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/models/recorded_observation_frame.dart';
import 'package:pov_agent/features/camera/application/models/recorded_video_frame.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_frame_detector.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_video_frame_source.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_snapshot.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';

const _recordedObservationFrameInterval = Duration(milliseconds: 200);

/// A factory for periodic replay timers used by [RecordedObservationAdapter].
@visibleForTesting
typedef RecordedReplayTimerFactory =
    Timer Function(
      Duration interval,
      void Function() onTick,
    );

/// An adapter that runs decoded video frames through single-image inference.
///
/// Lifecycle:
/// - [init] prepares the detector and recorded-video source in parallel.
/// - [enable] records playback demand; replay starts only when both are ready.
/// - Each replay iteration pulls one frame, runs detection, and publishes the
///   image together with its synchronized detections and diagnostics.
/// - [disable], retries, and [close] stop replay and invalidate results from
///   the affected generation before they can publish into the next phase.
///
/// Concurrency policy: drop timer ticks while frame decoding or inference is
/// active. Disable, retry, and close revise the replay so stale work cannot
/// publish. The adapter joins decoder/model work before disposing either
/// native runtime.
final class RecordedObservationAdapter implements ObservationController, RecordedObservationFrameSource {
  /// Creates an adapter using periodic replay timers.
  factory RecordedObservationAdapter({
    required RecordedFrameDetector detector,
    required RecordedVideoFrameSource frameSource,
    ObservationConfiguration configuration = ObservationConfiguration.milestoneOne,
    Duration frameInterval = _recordedObservationFrameInterval,
  }) {
    return RecordedObservationAdapter.withTimerFactory(
      detector,
      frameSource,
      _createReplayTimer,
      configuration: configuration,
      frameInterval: frameInterval,
    );
  }

  /// Creates an adapter with an injectable [RecordedReplayTimerFactory].
  ///
  /// The injected factory makes scheduling deterministic in tests without
  /// changing the adapter's drop-while-busy concurrency policy.
  @visibleForTesting
  RecordedObservationAdapter.withTimerFactory(
    this._detector,
    this._frameSource,
    this._timerFactory, {
    this.configuration = ObservationConfiguration.milestoneOne,
    this.frameInterval = _recordedObservationFrameInterval,
  });

  /// The model and inference configuration used by this adapter.
  final ObservationConfiguration configuration;

  /// The interval between recorded frame requests.
  final Duration frameInterval;
  final RecordedFrameDetector _detector;
  final RecordedVideoFrameSource _frameSource;
  final RecordedReplayTimerFactory _timerFactory;
  final StreamController<ObservationEvent> _eventsController = StreamController<ObservationEvent>.broadcast();
  final StreamController<RecordedObservationFrame> _framesController =
      StreamController<RecordedObservationFrame>.broadcast();

  StreamSubscription<DownloadProgress>? _downloadSubscription;

  // Task slots are identity-tracked so an older completion cannot clear a
  // newer task installed by retry or decoder reopening.
  Future<void>? _modelLoadTask;
  Future<void>? _frameSourceOpenTask;
  Future<void>? _activeReplayTask;
  Timer? _replayTimer;
  RecordedObservationFrame? _currentFrame;
  RecordedVideoMetadata? _videoMetadata;
  AppFailure? _frameSourceFailure;
  DateTime? _lastObservationAt;
  var _frameNumber = 0;

  // Generation tokens reject completions from superseded model, source, or
  // replay work before those completions can mutate or publish current state.
  var _modelLoadRevision = 0;
  var _frameSourceOpenRevision = 0;
  var _replayRevision = 0;
  var _initialized = false;
  var _modelReady = false;
  var _frameSourceReady = false;
  var _requestedEnabled = false;
  var _closed = false;

  @override
  Stream<ObservationEvent> get events => _eventsController.stream;

  @override
  Stream<RecordedObservationFrame> get frames => _framesController.stream;

  @override
  RecordedObservationFrame? get currentFrame => _currentFrame;

  @override
  Future<AppResult<CameraCapabilities>> init() async {
    if (_closed) return _closedResult();
    if (!_initialized) {
      _initialized = true;
      _downloadSubscription = YOLOModelManager.downloadProgress.listen(
        _handleDownloadProgress,
      );
      _eventsController.add(const ObservationModelPreparing());

      // Model and decoder preparation are independent. Warm both in parallel;
      // replay remains gated by enable and both readiness flags.
      _openFrameSourceIfNeeded();
      _ensureModelLoading();
    }

    // A virtual back lens preserves the existing power contract while the
    // platform decoder owns the recorded input instead of camera hardware.
    return AppSuccess(
      CameraCapabilities(
        availableLenses: const [CameraLens.back],
        preferredLens: CameraLens.back,
      ),
    );
  }

  @override
  Future<AppResult<void>> enable(CameraLens lens) async {
    if (_closed) return _closedResult();
    _requestedEnabled = true;
    if (!_frameSourceReady) _openFrameSourceIfNeeded();
    _startReplayIfReady();
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> disable() async {
    if (_closed) return _closedResult();
    _requestedEnabled = false;
    _stopReplay();
    // Invalidation rejects the result immediately; joining the captured task
    // additionally guarantees that another native runtime is not torn down
    // while this detector still owns an inference command buffer.
    await _activeReplayTask;
    if (_closed) return _closedResult();
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryModel() async {
    if (_closed) return _closedResult();
    _modelReady = false;
    _modelLoadRevision += 1;
    _stopReplay();
    _clearDetections();
    _eventsController.add(const ObservationModelPreparing());
    await _activeReplayTask;
    final activeLoad = _modelLoadTask;
    await activeLoad;
    if (_closed) return _closedResult();
    if (identical(_modelLoadTask, activeLoad)) _modelLoadTask = null;
    _ensureModelLoading();
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryObservation() async {
    if (_closed) return _closedResult();
    _stopReplay();
    await _activeReplayTask;
    await _frameSourceOpenTask;
    if (_closed) return _closedResult();
    _clearDetections();

    if (_frameSourceReady) {
      _startReplayIfReady();
      return const AppSuccess<void>(null);
    }

    _frameSourceFailure = null;
    _openFrameSourceIfNeeded();
    return const AppSuccess<void>(null);
  }

  AppResult<T> _closedResult<T>() {
    return AppError<T>(
      const DeviceUnavailableFailure(code: 'observation_closed'),
    );
  }

  // ── Model preparation ──────────────────────────────────────────────

  void _ensureModelLoading() {
    if (_closed || _modelLoadTask != null) return;
    final revision = ++_modelLoadRevision;
    final modelLoadTask = _runModelLoad(revision);
    _modelLoadTask = modelLoadTask;
    unawaited(_clearModelLoadTaskOnCompletion(modelLoadTask));
  }

  Future<void> _clearModelLoadTaskOnCompletion(
    Future<void> modelLoadTask,
  ) async {
    try {
      await modelLoadTask;
    } finally {
      if (identical(_modelLoadTask, modelLoadTask)) _modelLoadTask = null;
    }
  }

  Future<void> _runModelLoad(int revision) async {
    final result = await _detector.load();
    if (_closed || revision != _modelLoadRevision) return;

    switch (result) {
      case AppSuccess<void>():
        _modelReady = true;
        _eventsController.add(const ObservationModelReady());
        final frameSourceFailure = _frameSourceFailure;
        if (frameSourceFailure == null) {
          _startReplayIfReady();
        } else {
          _eventsController.add(
            ObservationInferenceFailed(frameSourceFailure),
          );
        }
      case AppError<void>(:final failure):
        _modelReady = false;
        _eventsController.add(ObservationFailed(failure));
    }
  }

  void _handleDownloadProgress(DownloadProgress progress) {
    if (_closed || progress.modelId != configuration.modelPath) return;
    _eventsController.add(
      ObservationModelDownloadProgressed(progress.fraction),
    );
  }

  // ── Recorded-video source lifecycle ────────────────────────────────

  void _openFrameSourceIfNeeded() {
    if (_closed || _frameSourceReady || _frameSourceOpenTask != null) return;
    final activeReplayTask = _activeReplayTask;
    if (activeReplayTask != null) {
      // A failed frame pull closes the decoder inside the active replay task.
      // Join that task before reopening so close/open cannot overlap at the
      // application port when the user quickly disables and re-enables.
      unawaited(
        _waitForReplayThenOpenFrameSource(activeReplayTask),
      );
      return;
    }
    final revision = ++_frameSourceOpenRevision;
    final frameSourceOpenTask = _openFrameSource(revision);
    _frameSourceOpenTask = frameSourceOpenTask;
    unawaited(
      _clearFrameSourceOpenTaskOnCompletion(frameSourceOpenTask),
    );
  }

  Future<void> _waitForReplayThenOpenFrameSource(
    Future<void> activeReplayTask,
  ) async {
    await activeReplayTask;
    _openFrameSourceIfNeeded();
  }

  Future<void> _clearFrameSourceOpenTaskOnCompletion(
    Future<void> frameSourceOpenTask,
  ) async {
    try {
      await frameSourceOpenTask;
    } finally {
      if (identical(_frameSourceOpenTask, frameSourceOpenTask)) {
        _frameSourceOpenTask = null;
      }
    }
  }

  Future<void> _openFrameSource(int revision) async {
    final result = await _frameSource.open();
    if (_closed || revision != _frameSourceOpenRevision) return;

    switch (result) {
      case AppSuccess(value: final metadata):
        _videoMetadata = metadata;
        _frameSourceFailure = null;
        _frameSourceReady = true;
        _startReplayIfReady();
      case AppError(:final failure):
        // A native open may succeed before Dart rejects malformed metadata.
        // Close defensively so every failed open remains transactional.
        await _frameSource.close();
        if (_closed || revision != _frameSourceOpenRevision) return;
        _videoMetadata = null;
        _frameSourceFailure = failure;
        _frameSourceReady = false;
        if (_modelReady) {
          _eventsController.add(ObservationInferenceFailed(failure));
        }
    }
  }

  // ── Replay and inference loop ──────────────────────────────────────

  void _startReplayIfReady() {
    // Replay is a three-way barrier between user demand, model readiness, and
    // decoder readiness; no individual completion may bypass the other two.
    if (_closed || !_requestedEnabled || !_modelReady || !_frameSourceReady || _replayTimer != null) {
      return;
    }
    _replayRevision += 1;
    _replayTimer = _timerFactory(
      frameInterval,
      _startNextFrameIfIdle,
    );
    _startNextFrameIfIdle();
  }

  void _stopReplay() {
    _replayRevision += 1;
    _replayTimer?.cancel();
    _replayTimer = null;
    _lastObservationAt = null;
  }

  void _startNextFrameIfIdle() {
    // Busy ticks are deliberately dropped instead of queued so slow decoding
    // or inference cannot build an unbounded frame backlog.
    if (_closed || !_requestedEnabled || !_modelReady || !_frameSourceReady || _activeReplayTask != null) {
      return;
    }
    final replayTask = _decodeAndDetectNextFrame(_replayRevision);
    _activeReplayTask = replayTask;
    unawaited(_clearActiveReplayTaskOnCompletion(replayTask));
  }

  Future<void> _clearActiveReplayTaskOnCompletion(
    Future<void> replayTask,
  ) async {
    try {
      await replayTask;
    } finally {
      if (identical(_activeReplayTask, replayTask)) _activeReplayTask = null;
    }
  }

  Future<void> _decodeAndDetectNextFrame(int revision) async {
    final frameResult = await _frameSource.nextFrame();
    if (!_canPublishReplayResult(revision)) return;

    switch (frameResult) {
      case AppError(:final failure):
        await _handleFrameSourceFailure(failure);
      case AppSuccess(value: final decodedFrame):
        final metadata = _videoMetadata;
        if (metadata == null) {
          await _handleFrameSourceFailure(
            const UnexpectedFailure(
              code: 'recorded_video_metadata_missing',
            ),
          );
          return;
        }
        final result = await _detector.detect(decodedFrame.encodedImage);
        if (!_canPublishReplayResult(revision)) return;
        _publishInferenceResult(
          result,
          decodedFrame,
          metadata,
        );
    }
  }

  bool _canPublishReplayResult(int revision) {
    return !_closed && revision == _replayRevision && _requestedEnabled && _modelReady && _frameSourceReady;
  }

  Future<void> _handleFrameSourceFailure(AppFailure failure) async {
    _frameSourceReady = false;
    _frameSourceFailure = failure;
    _stopReplay();
    _clearDetections();
    if (_requestedEnabled) {
      _eventsController.add(ObservationInferenceFailed(failure));
    }
    // A frame transport failure invalidates the decoder session. Close it
    // before a later enable or retry is allowed to reopen the source.
    await _frameSource.close();
  }

  // ── Frame and event publication ────────────────────────────────────

  void _publishInferenceResult(
    AppResult<ObservationSnapshot> result,
    RecordedVideoFrame decodedFrame,
    RecordedVideoMetadata metadata,
  ) {
    switch (result) {
      case AppSuccess(value: final snapshot):
        _frameNumber += 1;
        final previousObservationAt = _lastObservationAt;
        _lastObservationAt = snapshot.observedAt;
        final framesPerSecond = previousObservationAt == null
            ? 0.0
            : _framesPerSecond(
                previousObservationAt,
                snapshot.observedAt,
              );
        _publishFrame(
          RecordedObservationFrame(
            encodedImage: decodedFrame.encodedImage,
            detections: snapshot.detections,
            frameNumber: _frameNumber,
            frameWidth: metadata.frameWidth,
            frameHeight: metadata.frameHeight,
          ),
        );
        _eventsController
          ..add(
            ObservationDetectionsUpdated(
              detections: snapshot.detections,
              observedAt: snapshot.observedAt,
            ),
          )
          ..add(
            ObservationDiagnosticsUpdated(
              ObservationDiagnostics(
                framesPerSecond: framesPerSecond,
                inferenceTimeMs: snapshot.processingTimeMs,
                processingTimeMs: snapshot.processingTimeMs,
                frameNumber: _frameNumber,
                sampledAt: snapshot.observedAt,
              ),
            ),
          );
      case AppError(:final failure):
        _stopReplay();
        _clearDetections();
        _eventsController.add(ObservationInferenceFailed(failure));
    }
  }

  void _clearDetections() {
    final frame = _currentFrame;
    if (frame == null) return;
    // Keep the last decoded image mounted while removing stale boxes
    // immediately after inference or frame transport fails.
    _publishFrame(
      RecordedObservationFrame(
        encodedImage: frame.encodedImage,
        detections: const [],
        frameNumber: frame.frameNumber,
        frameWidth: frame.frameWidth,
        frameHeight: frame.frameHeight,
      ),
    );
  }

  void _publishFrame(RecordedObservationFrame frame) {
    _currentFrame = frame;
    if (!_framesController.isClosed) _framesController.add(frame);
  }

  // ── Shutdown ───────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _requestedEnabled = false;
    _modelLoadRevision += 1;
    _frameSourceOpenRevision += 1;
    _stopReplay();
    YOLOModelManager.cancelDownload(configuration.modelPath);
    await _downloadSubscription?.cancel();
    try {
      final pendingTasks = [
        ?_modelLoadTask,
        ?_frameSourceOpenTask,
        ?_activeReplayTask,
      ];
      await Future.wait(pendingTasks);
    } finally {
      // Keep the pre-registration marker until model resolution settles, then
      // clear it so a later app runtime cannot inherit stale cancellation.
      YOLOModelManager.clearDownloadCancellation(configuration.modelPath);
    }
    await _frameSource.close();
    await _detector.close();
    await _framesController.close();
    await _eventsController.close();
  }
}

Timer _createReplayTimer(Duration interval, void Function() onTick) {
  return Timer.periodic(interval, (_) => onTick());
}

double _framesPerSecond(DateTime previous, DateTime current) {
  final elapsedMicroseconds = current.difference(previous).inMicroseconds;
  if (elapsedMicroseconds <= 0) return 0;
  return Duration.microsecondsPerSecond / elapsedMicroseconds;
}
