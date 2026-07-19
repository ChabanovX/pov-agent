import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/models/recorded_video_frame.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_frame_detector.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_video_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/features/camera/domain/entities/observation_snapshot.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';

void main() {
  test('opens video and pulls frames only while enabled', () async {
    final detector = _FakeRecordedFrameDetector();
    final frameSource = _FakeRecordedVideoFrameSource();
    final timers = <_ManualTimer>[];
    final adapter = _createAdapter(
      detector,
      frameSource: frameSource,
      timerFactory: (interval, onTick) {
        final timer = _ManualTimer(onTick);
        timers.add(timer);
        return timer;
      },
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    expect(adapter.currentFrame, isNull);
    final initResult = await adapter.init();
    await _flushMicrotasks();

    expect(initResult, isA<AppSuccess<CameraCapabilities>>());
    final capabilities = (initResult as AppSuccess<CameraCapabilities>).value;
    expect(capabilities.availableLenses, [CameraLens.back]);
    expect(capabilities.canToggleLens, isFalse);
    expect(frameSource.openCalls, 1);
    expect(events, contains(isA<ObservationModelReady>()));
    expect(timers, isEmpty);

    expect(await adapter.enable(CameraLens.back), isA<AppSuccess<void>>());
    await _flushMicrotasks();

    expect(timers, hasLength(1));
    expect(frameSource.nextFrameCalls, 1);
    expect(detector.detectCalls, 1);
    expect(adapter.currentFrame?.detections.single.label, 'person');
    expect(adapter.currentFrame?.frameWidth, 320);
    expect(adapter.currentFrame?.frameHeight, 240);
    expect(events, contains(isA<ObservationDetectionsUpdated>()));
    expect(events, contains(isA<ObservationDiagnosticsUpdated>()));

    await adapter.disable();
    timers.single.fire();
    await _flushMicrotasks();
    expect(frameSource.nextFrameCalls, 1);

    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();
    expect(timers, hasLength(2));
    expect(frameSource.nextFrameCalls, 2);

    await subscription.cancel();
    await adapter.close();
  });

  test('drops busy ticks and rejects inference after disable', () async {
    final firstDetection = Completer<AppResult<ObservationSnapshot>>();
    final detector = _FakeRecordedFrameDetector(
      onDetect: (call, _) {
        if (call == 1) return firstDetection.future;
        return Future.value(AppSuccess(_snapshot(call)));
      },
    );
    final frameSource = _FakeRecordedVideoFrameSource();
    late _ManualTimer timer;
    final adapter = _createAdapter(
      detector,
      frameSource: frameSource,
      timerFactory: (interval, onTick) {
        return timer = _ManualTimer(onTick);
      },
    );
    final detections = <ObservationDetectionsUpdated>[];
    final subscription = adapter.events
        .where((event) => event is ObservationDetectionsUpdated)
        .cast<ObservationDetectionsUpdated>()
        .listen(detections.add);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();
    expect(frameSource.nextFrameCalls, 1);
    expect(detector.detectCalls, 1);

    timer
      ..fire()
      ..fire();
    await _flushMicrotasks();
    expect(frameSource.nextFrameCalls, 1);

    var disableCompleted = false;
    final disableFuture = adapter.disable().whenComplete(
      () => disableCompleted = true,
    );
    await _flushMicrotasks();
    expect(disableCompleted, isFalse);
    firstDetection.complete(AppSuccess(_snapshot(1)));
    expect(await disableFuture, isA<AppSuccess<void>>());

    expect(detections, isEmpty);
    expect(adapter.currentFrame, isNull);

    await subscription.cancel();
    await adapter.close();
  });

  test('does not infer a decoded frame completed after disable', () async {
    final pendingFrame = Completer<AppResult<RecordedVideoFrame>>();
    final frameSource = _FakeRecordedVideoFrameSource(
      onNextFrame: (_) => pendingFrame.future,
    );
    final detector = _FakeRecordedFrameDetector();
    final adapter = _createAdapter(detector, frameSource: frameSource);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();
    expect(frameSource.nextFrameCalls, 1);

    var disableCompleted = false;
    final disableFuture = adapter.disable().whenComplete(
      () => disableCompleted = true,
    );
    await _flushMicrotasks();
    expect(disableCompleted, isFalse);
    pendingFrame.complete(AppSuccess(_videoFrame(1)));
    expect(await disableFuture, isA<AppSuccess<void>>());

    expect(detector.detectCalls, 0);
    expect(adapter.currentFrame, isNull);

    await adapter.close();
  });

  test('retry cannot be overtaken by a stale decoded frame', () async {
    final pendingFrame = Completer<AppResult<RecordedVideoFrame>>();
    final frameSource = _FakeRecordedVideoFrameSource(
      onNextFrame: (call) {
        if (call == 1) return pendingFrame.future;
        return Future.value(AppSuccess(_videoFrame(call)));
      },
    );
    final detector = _FakeRecordedFrameDetector();
    final adapter = _createAdapter(detector, frameSource: frameSource);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();

    final retryFuture = adapter.retryObservation();
    await _flushMicrotasks();
    pendingFrame.complete(AppSuccess(_videoFrame(1)));
    await retryFuture;
    await _flushMicrotasks();

    expect(frameSource.nextFrameCalls, 2);
    expect(detector.detectCalls, 1);
    expect(adapter.currentFrame?.encodedImage, _videoFrame(2).encodedImage);

    await adapter.close();
  });

  test('retries a failed model load without reopening video', () async {
    final detector = _FakeRecordedFrameDetector(
      loadResults: Queue.of([
        const AppError<void>(NetworkFailure(code: 'model_download')),
        const AppSuccess<void>(null),
      ]),
    );
    final frameSource = _FakeRecordedVideoFrameSource();
    final adapter = _createAdapter(detector, frameSource: frameSource);
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await _flushMicrotasks();
    expect(events.last, isA<ObservationFailed>());

    await adapter.retryModel();
    await _flushMicrotasks();

    expect(detector.loadCalls, 2);
    expect(frameSource.openCalls, 1);
    expect(events.last, isA<ObservationModelReady>());

    await subscription.cancel();
    await adapter.close();
  });

  test('reports decoder open failure after model readiness and reopens on retry', () async {
    final frameSource = _FakeRecordedVideoFrameSource(
      openResults: Queue.of([
        const AppError<RecordedVideoMetadata>(
          DeviceUnavailableFailure(code: 'decoder_failed'),
        ),
        const AppSuccess(_metadata),
      ]),
    );
    final detector = _FakeRecordedFrameDetector();
    final adapter = _createAdapter(detector, frameSource: frameSource);
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await _flushMicrotasks();

    expect(events, contains(isA<ObservationModelReady>()));
    expect(events.last, isA<ObservationInferenceFailed>());
    expect(frameSource.closeCalls, 1);

    await adapter.retryObservation();
    await _flushMicrotasks();

    expect(frameSource.openCalls, 2);
    expect(detector.loadCalls, 1);

    await subscription.cancel();
    await adapter.close();
  });

  test('waits for video open before closing native resources', () async {
    final openResult = Completer<AppResult<RecordedVideoMetadata>>();
    final frameSource = _FakeRecordedVideoFrameSource(
      onOpen: (_) => openResult.future,
    );
    final detector = _FakeRecordedFrameDetector();
    final adapter = _createAdapter(detector, frameSource: frameSource);

    await adapter.init();
    final closeFuture = adapter.close();
    await _flushMicrotasks();

    expect(frameSource.closeCalls, 0);
    expect(detector.closeCalls, 0);

    openResult.complete(const AppSuccess(_metadata));
    await closeFuture;

    expect(frameSource.closeCalls, 1);
    expect(detector.closeCalls, 1);
  });

  test('waits for in-flight inference before closing native resources', () async {
    final detection = Completer<AppResult<ObservationSnapshot>>();
    final detector = _FakeRecordedFrameDetector(
      onDetect: (_, _) => detection.future,
    );
    final frameSource = _FakeRecordedVideoFrameSource();
    final adapter = _createAdapter(detector, frameSource: frameSource);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();

    final closeFuture = adapter.close();
    await _flushMicrotasks();
    expect(frameSource.closeCalls, 0);
    expect(detector.closeCalls, 0);

    detection.complete(AppSuccess(_snapshot(1)));
    await closeFuture;
    expect(frameSource.closeCalls, 1);
    expect(detector.closeCalls, 1);
  });

  test('waits for an in-flight decode before closing native resources', () async {
    final pendingFrame = Completer<AppResult<RecordedVideoFrame>>();
    final frameSource = _FakeRecordedVideoFrameSource(
      onNextFrame: (_) => pendingFrame.future,
    );
    final detector = _FakeRecordedFrameDetector();
    final adapter = _createAdapter(detector, frameSource: frameSource);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();

    final closeFuture = adapter.close();
    await _flushMicrotasks();
    expect(frameSource.closeCalls, 0);
    expect(detector.closeCalls, 0);

    pendingFrame.complete(AppSuccess(_videoFrame(1)));
    await closeFuture;

    expect(detector.detectCalls, 0);
    expect(frameSource.closeCalls, 1);
    expect(detector.closeCalls, 1);
  });

  test('keeps late model-download cancellation until load settles', () async {
    const modelId = 'yolo26n';
    final load = Completer<AppResult<void>>();
    final detector = _FakeRecordedFrameDetector(onLoad: (_) => load.future);
    final adapter = _createAdapter(
      detector,
      frameSource: _FakeRecordedVideoFrameSource(),
    );

    await adapter.init();
    final closeFuture = adapter.close();
    var cancelled = false;
    final token = YOLOModelManager.registerDownload(
      modelId,
      () => cancelled = true,
    );
    try {
      expect(cancelled, isTrue);
      load.complete(const AppSuccess<void>(null));
      await closeFuture;
    } finally {
      YOLOModelManager.finishDownload(modelId, token);
      YOLOModelManager.clearDownloadCancellation(modelId);
    }
  });

  test('publishes read-only decoded frame bytes', () async {
    final adapter = _createAdapter(
      _FakeRecordedFrameDetector(),
      frameSource: _FakeRecordedVideoFrameSource(),
    );

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();

    expect(
      () => adapter.currentFrame!.encodedImage[0] = 0,
      throwsA(isA<UnsupportedError>()),
    );

    await adapter.close();
  });

  test('clears stale boxes and retries inference without reopening video', () async {
    final detector = _FakeRecordedFrameDetector(
      onDetect: (call, _) async {
        if (call == 2) {
          return const AppError<ObservationSnapshot>(
            DeviceUnavailableFailure(code: 'inference_failed'),
          );
        }
        return AppSuccess(_snapshot(call));
      },
    );
    final frameSource = _FakeRecordedVideoFrameSource();
    final timers = <_ManualTimer>[];
    final adapter = _createAdapter(
      detector,
      frameSource: frameSource,
      timerFactory: (interval, onTick) {
        final timer = _ManualTimer(onTick);
        timers.add(timer);
        return timer;
      },
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();
    expect(adapter.currentFrame?.detections, isNotEmpty);

    timers.single.fire();
    await _flushMicrotasks();
    expect(events.last, isA<ObservationInferenceFailed>());
    expect(adapter.currentFrame?.detections, isEmpty);

    await adapter.retryObservation();
    await _flushMicrotasks();
    expect(detector.loadCalls, 1);
    expect(frameSource.openCalls, 1);
    expect(detector.detectCalls, 3);
    expect(adapter.currentFrame?.detections.single.label, 'person');

    await subscription.cancel();
    await adapter.close();
  });

  test('reopens decoder when re-enabled after a frame transport failure', () async {
    final closeResult = Completer<AppResult<void>>();
    final frameSource = _FakeRecordedVideoFrameSource(
      frameResults: Queue.of([
        AppSuccess(_videoFrame(1)),
        const AppError<RecordedVideoFrame>(
          DeviceUnavailableFailure(code: 'frame_decode_failed'),
        ),
        AppSuccess(_videoFrame(3)),
      ]),
      onClose: (_) => closeResult.future,
    );
    final detector = _FakeRecordedFrameDetector();
    final timers = <_ManualTimer>[];
    final adapter = _createAdapter(
      detector,
      frameSource: frameSource,
      timerFactory: (interval, onTick) {
        final timer = _ManualTimer(onTick);
        timers.add(timer);
        return timer;
      },
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();
    timers.single.fire();
    await _flushMicrotasks();

    expect(events.last, isA<ObservationInferenceFailed>());
    expect(frameSource.closeCalls, 1);

    var disableCompleted = false;
    final disableFuture = adapter.disable().whenComplete(
      () => disableCompleted = true,
    );
    await _flushMicrotasks();

    expect(disableCompleted, isFalse);
    expect(frameSource.openCalls, 1);

    closeResult.complete(const AppSuccess<void>(null));
    expect(await disableFuture, isA<AppSuccess<void>>());
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();

    expect(frameSource.openCalls, 2);
    expect(detector.loadCalls, 1);
    expect(adapter.currentFrame?.encodedImage, _videoFrame(3).encodedImage);

    await subscription.cancel();
    await adapter.close();
  });
}

const _metadata = RecordedVideoMetadata(
  frameWidth: 320,
  frameHeight: 240,
  duration: Duration(seconds: 4),
);

RecordedObservationAdapter _createAdapter(
  RecordedFrameDetector detector, {
  required RecordedVideoFrameSource frameSource,
  RecordedReplayTimerFactory? timerFactory,
}) {
  return RecordedObservationAdapter.withTimerFactory(
    detector,
    frameSource,
    timerFactory ?? _unusedTimerFactory,
  );
}

Timer _unusedTimerFactory(Duration interval, void Function() onTick) {
  return _ManualTimer(onTick);
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

final class _FakeRecordedVideoFrameSource implements RecordedVideoFrameSource {
  _FakeRecordedVideoFrameSource({
    Queue<AppResult<RecordedVideoMetadata>>? openResults,
    Queue<AppResult<RecordedVideoFrame>>? frameResults,
    this.onOpen,
    this.onNextFrame,
    this.onClose,
  }) : openResults = openResults ?? Queue.of([const AppSuccess(_metadata)]),
       frameResults = frameResults ?? Queue<AppResult<RecordedVideoFrame>>();

  final Queue<AppResult<RecordedVideoMetadata>> openResults;
  final Queue<AppResult<RecordedVideoFrame>> frameResults;
  final Future<AppResult<RecordedVideoMetadata>> Function(int call)? onOpen;
  final Future<AppResult<RecordedVideoFrame>> Function(int call)? onNextFrame;
  final Future<AppResult<void>> Function(int call)? onClose;
  int openCalls = 0;
  int nextFrameCalls = 0;
  int closeCalls = 0;

  @override
  Future<AppResult<RecordedVideoMetadata>> open() async {
    openCalls += 1;
    final handler = onOpen;
    if (handler != null) return handler(openCalls);
    if (openResults.length > 1) return openResults.removeFirst();
    return openResults.first;
  }

  @override
  Future<AppResult<RecordedVideoFrame>> nextFrame() async {
    nextFrameCalls += 1;
    final handler = onNextFrame;
    if (handler != null) return handler(nextFrameCalls);
    if (frameResults.isNotEmpty) return frameResults.removeFirst();
    return AppSuccess(_videoFrame(nextFrameCalls));
  }

  @override
  Future<AppResult<void>> close() async {
    closeCalls += 1;
    final handler = onClose;
    if (handler != null) return handler(closeCalls);
    return const AppSuccess<void>(null);
  }
}

RecordedVideoFrame _videoFrame(int frameNumber) {
  return RecordedVideoFrame(
    encodedImage: Uint8List.fromList([0xFF, 0xD8, frameNumber, 0xFF, 0xD9]),
    sourceFrameNumber: frameNumber,
    presentationTime: Duration(milliseconds: frameNumber * 200),
  );
}

final class _FakeRecordedFrameDetector implements RecordedFrameDetector {
  _FakeRecordedFrameDetector({
    Queue<AppResult<void>>? loadResults,
    this.onLoad,
    this.onDetect,
  }) : loadResults = loadResults ?? Queue.of([const AppSuccess<void>(null)]);

  final Queue<AppResult<void>> loadResults;
  final Future<AppResult<void>> Function(int call)? onLoad;
  final Future<AppResult<ObservationSnapshot>> Function(
    int call,
    Uint8List encodedImage,
  )?
  onDetect;

  int loadCalls = 0;
  int detectCalls = 0;
  int closeCalls = 0;

  @override
  Future<AppResult<void>> load() async {
    loadCalls += 1;
    final handler = onLoad;
    if (handler != null) return handler(loadCalls);
    return loadResults.removeFirst();
  }

  @override
  Future<AppResult<ObservationSnapshot>> detect(Uint8List encodedImage) async {
    detectCalls += 1;
    final handler = onDetect;
    if (handler != null) return handler(detectCalls, encodedImage);
    return AppSuccess(_snapshot(detectCalls));
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this._onTick);

  final void Function() _onTick;
  var _active = true;
  var _tick = 0;

  void fire() {
    if (!_active) return;
    _tick += 1;
    _onTick();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }
}

ObservationSnapshot _snapshot(int frameNumber) {
  return ObservationSnapshot(
    detections: const [
      Detection(
        classId: 0,
        label: 'person',
        confidence: 0.9,
        box: NormalizedBox(
          left: 0.1,
          top: 0.2,
          right: 0.6,
          bottom: 0.9,
        ),
      ),
    ],
    processingTimeMs: 12,
    observedAt: DateTime.utc(2026, 7, 17).add(
      Duration(milliseconds: frameNumber * 200),
    ),
  );
}
