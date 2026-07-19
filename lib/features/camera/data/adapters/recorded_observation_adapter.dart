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
  Future<void>? _loadFuture;
  Future<void>? _frameSourceOpenFuture;
  Future<void>? _activeInference;
  Timer? _replayTimer;
  RecordedObservationFrame? _currentFrame;
  RecordedVideoMetadata? _videoMetadata;
  AppFailure? _frameSourceFailure;
  DateTime? _lastObservationAt;
  var _frameNumber = 0;
  var _loadRevision = 0;
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
      _startFrameSourceOpen();
      _startModelLoad();
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
    if (!_frameSourceReady) _startFrameSourceOpen();
    _startReplayIfReady();
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> disable() async {
    if (_closed) return _closedResult();
    _requestedEnabled = false;
    _stopReplay();
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryModel() async {
    if (_closed) return _closedResult();
    _modelReady = false;
    _loadRevision += 1;
    _stopReplay();
    _clearDetections();
    _eventsController.add(const ObservationModelPreparing());
    await _activeInference;
    final activeLoad = _loadFuture;
    await activeLoad;
    if (_closed) return _closedResult();
    if (identical(_loadFuture, activeLoad)) _loadFuture = null;
    _startModelLoad();
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> retryObservation() async {
    if (_closed) return _closedResult();
    _stopReplay();
    await _activeInference;
    await _frameSourceOpenFuture;
    if (_closed) return _closedResult();
    _clearDetections();

    if (_frameSourceReady) {
      _startReplayIfReady();
      return const AppSuccess<void>(null);
    }

    _frameSourceFailure = null;
    _startFrameSourceOpen();
    return const AppSuccess<void>(null);
  }

  void _startModelLoad() {
    if (_closed || _loadFuture != null) return;
    final revision = ++_loadRevision;
    final loadFuture = _loadModel(revision);
    _loadFuture = loadFuture;
    unawaited(_releaseLoadFuture(loadFuture));
  }

  Future<void> _releaseLoadFuture(Future<void> loadFuture) async {
    try {
      await loadFuture;
    } finally {
      if (identical(_loadFuture, loadFuture)) _loadFuture = null;
    }
  }

  Future<void> _loadModel(int revision) async {
    final result = await _detector.load();
    if (_closed || revision != _loadRevision) return;

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

  void _startFrameSourceOpen() {
    if (_closed || _frameSourceReady || _frameSourceOpenFuture != null) return;
    final activeInference = _activeInference;
    if (activeInference != null) {
      // A failed frame pull closes the decoder inside the active replay task.
      // Join that task before reopening so close/open cannot overlap at the
      // application port when the user quickly disables and re-enables.
      unawaited(_startFrameSourceOpenAfter(activeInference));
      return;
    }
    final revision = ++_frameSourceOpenRevision;
    final openFuture = _openFrameSource(revision);
    _frameSourceOpenFuture = openFuture;
    unawaited(_releaseFrameSourceOpenFuture(openFuture));
  }

  Future<void> _startFrameSourceOpenAfter(Future<void> activeInference) async {
    await activeInference;
    _startFrameSourceOpen();
  }

  Future<void> _releaseFrameSourceOpenFuture(Future<void> openFuture) async {
    try {
      await openFuture;
    } finally {
      if (identical(_frameSourceOpenFuture, openFuture)) {
        _frameSourceOpenFuture = null;
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

  void _startReplayIfReady() {
    if (_closed || !_requestedEnabled || !_modelReady || !_frameSourceReady || _replayTimer != null) {
      return;
    }
    _replayRevision += 1;
    _replayTimer = _timerFactory(
      frameInterval,
      _scheduleNextFrame,
    );
    _scheduleNextFrame();
  }

  void _stopReplay() {
    _replayRevision += 1;
    _replayTimer?.cancel();
    _replayTimer = null;
    _lastObservationAt = null;
  }

  void _scheduleNextFrame() {
    if (_closed || !_requestedEnabled || !_modelReady || !_frameSourceReady || _activeInference != null) {
      return;
    }
    final inference = _processNextFrame(_replayRevision);
    _activeInference = inference;
    unawaited(_releaseInferenceFuture(inference));
  }

  Future<void> _releaseInferenceFuture(Future<void> inference) async {
    try {
      await inference;
    } finally {
      if (identical(_activeInference, inference)) _activeInference = null;
    }
  }

  Future<void> _processNextFrame(int revision) async {
    final frameResult = await _frameSource.nextFrame();
    if (!_canPublishReplay(revision)) return;

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
        if (!_canPublishReplay(revision)) return;
        _handleDetectionResult(
          result,
          decodedFrame,
          metadata,
        );
    }
  }

  bool _canPublishReplay(int revision) {
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
    await _frameSource.close();
  }

  void _handleDetectionResult(
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

  void _handleDownloadProgress(DownloadProgress progress) {
    if (_closed || progress.modelId != configuration.modelPath) return;
    _eventsController.add(
      ObservationModelDownloadProgressed(progress.fraction),
    );
  }

  AppResult<T> _closedResult<T>() {
    return AppError<T>(
      const DeviceUnavailableFailure(code: 'observation_closed'),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _requestedEnabled = false;
    _loadRevision += 1;
    _frameSourceOpenRevision += 1;
    _stopReplay();
    YOLOModelManager.cancelDownload(configuration.modelPath);
    await _downloadSubscription?.cancel();
    try {
      await _loadFuture;
      await _frameSourceOpenFuture;
      await _activeInference;
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
