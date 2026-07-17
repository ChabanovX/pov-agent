import 'dart:async';
import 'dart:typed_data';

import 'package:some_camera_with_llm/features/camera/application/models/observation_configuration.dart';
import 'package:some_camera_with_llm/features/camera/application/models/observation_event.dart';
import 'package:some_camera_with_llm/features/camera/application/models/recorded_observation_frame.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/observation_controller.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/recorded_frame_detector.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_diagnostics.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';

const _recordedObservationFrameInterval = Duration(milliseconds: 500);

/// Creates the periodic replay timer used by [RecordedObservationAdapter].
typedef RecordedReplayTimerFactory =
    Timer Function(
      Duration interval,
      void Function() onTick,
    );

/// Replays encoded frames through the production single-image YOLO runtime.
///
/// Concurrency policy: drop timer ticks while inference is active. Disabling,
/// retrying, or closing increments the replay revision so an in-flight result
/// cannot update a hidden or obsolete surface. Shutdown joins owned model and
/// inference work before disposing the detector.
final class RecordedObservationAdapter implements ObservationController, RecordedObservationFrameSource {
  factory RecordedObservationAdapter({
    required RecordedFrameDetector detector,
    required List<Uint8List> frames,
    required int frameWidth,
    required int frameHeight,
    ObservationConfiguration configuration = ObservationConfiguration.milestoneOne,
    Duration frameInterval = _recordedObservationFrameInterval,
  }) {
    return RecordedObservationAdapter.withTimerFactory(
      detector,
      _createReplayTimer,
      frames: frames,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      configuration: configuration,
      frameInterval: frameInterval,
    );
  }

  RecordedObservationAdapter.withTimerFactory(
    this._detector,
    this._timerFactory, {
    required List<Uint8List> frames,
    required this.frameWidth,
    required this.frameHeight,
    this.configuration = ObservationConfiguration.milestoneOne,
    this.frameInterval = _recordedObservationFrameInterval,
  }) : assert(frames.isNotEmpty, 'Recorded replay requires at least one frame.'),
       assert(frameWidth > 0, 'Recorded frame width must be positive.'),
       assert(frameHeight > 0, 'Recorded frame height must be positive.') {
    _frames = List.unmodifiable(
      frames.map(
        (frame) => Uint8List.fromList(frame).asUnmodifiableView(),
      ),
    );
    _currentFrame = RecordedObservationFrame(
      encodedImage: _frames.first,
      detections: const [],
      frameNumber: 0,
    );
  }

  final ObservationConfiguration configuration;
  final Duration frameInterval;
  final int frameWidth;
  final int frameHeight;
  final RecordedFrameDetector _detector;
  final RecordedReplayTimerFactory _timerFactory;
  late final List<Uint8List> _frames;
  late RecordedObservationFrame _currentFrame;
  final StreamController<ObservationEvent> _eventsController = StreamController<ObservationEvent>.broadcast();
  final StreamController<RecordedObservationFrame> _framesController =
      StreamController<RecordedObservationFrame>.broadcast();

  StreamSubscription<DownloadProgress>? _downloadSubscription;
  Future<void>? _loadFuture;
  Future<void>? _activeInference;
  Timer? _replayTimer;
  DateTime? _lastObservationAt;
  var _nextFrameIndex = 0;
  var _frameNumber = 0;
  var _loadRevision = 0;
  var _replayRevision = 0;
  var _initialized = false;
  var _modelReady = false;
  var _requestedEnabled = false;
  var _closed = false;

  @override
  Stream<ObservationEvent> get events => _eventsController.stream;

  @override
  Stream<RecordedObservationFrame> get frames => _framesController.stream;

  @override
  RecordedObservationFrame get currentFrame => _currentFrame;

  @override
  double get frameAspectRatio => frameWidth / frameHeight;

  @override
  Future<AppResult<CameraCapabilities>> init() async {
    if (_closed) return _closedResult();
    if (!_initialized) {
      _initialized = true;
      _downloadSubscription = YOLOModelManager.downloadProgress.listen(
        _handleDownloadProgress,
      );
      _eventsController.add(const ObservationModelPreparing());
      _startModelLoad();
    }

    // A single virtual lens keeps the existing observation power contract
    // while naturally hiding the live-only camera switch control.
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
    if (_closed) return _closedResult();
    _clearDetections();
    _startReplayIfReady();
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
        _startReplayIfReady();
      case AppError<void>(:final failure):
        _modelReady = false;
        _eventsController.add(ObservationFailed(failure));
    }
  }

  void _startReplayIfReady() {
    if (_closed || !_requestedEnabled || !_modelReady || _replayTimer != null) {
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
    if (_closed || !_requestedEnabled || !_modelReady || _activeInference != null) {
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
    final encodedImage = _frames[_nextFrameIndex];
    _nextFrameIndex = (_nextFrameIndex + 1) % _frames.length;
    final result = await _detector.detect(encodedImage);
    if (_closed || revision != _replayRevision || !_requestedEnabled || !_modelReady) {
      return;
    }

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
            encodedImage: encodedImage,
            detections: snapshot.detections,
            frameNumber: _frameNumber,
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
    _publishFrame(
      RecordedObservationFrame(
        encodedImage: frame.encodedImage,
        detections: const [],
        frameNumber: frame.frameNumber,
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
    _stopReplay();
    YOLOModelManager.cancelDownload(configuration.modelPath);
    await _downloadSubscription?.cancel();
    try {
      await _loadFuture;
      await _activeInference;
    } finally {
      // Keep the pre-registration marker until model resolution settles, then
      // clear it so a later app runtime does not inherit stale cancellation.
      YOLOModelManager.clearDownloadCancellation(configuration.modelPath);
    }
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
