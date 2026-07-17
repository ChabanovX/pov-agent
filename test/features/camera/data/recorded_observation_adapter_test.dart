import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/features/camera/application/models/observation_event.dart';
import 'package:some_camera_with_llm/features/camera/application/ports/recorded_frame_detector.dart';
import 'package:some_camera_with_llm/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:some_camera_with_llm/features/camera/data/debug/recorded_bus_fixture.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_capabilities.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/camera_lens.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/detection.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/normalized_box.dart';
import 'package:some_camera_with_llm/features/camera/domain/entities/observation_snapshot.dart';
import 'package:some_camera_with_llm/shared/domain/app_failure.dart';
import 'package:some_camera_with_llm/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';

void main() {
  test('loads and replays recorded frames only while enabled', () async {
    final detector = _FakeRecordedFrameDetector();
    final timers = <_ManualTimer>[];
    final adapter = _createAdapter(
      detector,
      timerFactory: (interval, onTick) {
        final timer = _ManualTimer(onTick);
        timers.add(timer);
        return timer;
      },
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    final initResult = await adapter.init();
    await _flushMicrotasks();

    expect(initResult, isA<AppSuccess<CameraCapabilities>>());
    final capabilities = (initResult as AppSuccess<CameraCapabilities>).value;
    expect(capabilities.availableLenses, [CameraLens.back]);
    expect(capabilities.canToggleLens, isFalse);
    expect(events, contains(isA<ObservationModelReady>()));
    expect(timers, isEmpty);

    expect(await adapter.enable(CameraLens.back), isA<AppSuccess<void>>());
    await _flushMicrotasks();

    expect(timers, hasLength(1));
    expect(detector.detectCalls, 1);
    expect(adapter.currentFrame.detections.single.label, 'person');
    expect(events, contains(isA<ObservationDetectionsUpdated>()));
    expect(events, contains(isA<ObservationDiagnosticsUpdated>()));

    await adapter.disable();
    timers.single.fire();
    await _flushMicrotasks();
    expect(detector.detectCalls, 1);

    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();
    expect(timers, hasLength(2));
    expect(detector.detectCalls, 2);

    await subscription.cancel();
    await adapter.close();
  });

  test('drops busy ticks and rejects a result after disable', () async {
    final firstDetection = Completer<AppResult<ObservationSnapshot>>();
    final detector = _FakeRecordedFrameDetector(
      onDetect: (call, _) {
        if (call == 1) return firstDetection.future;
        return Future.value(AppSuccess(_snapshot(call)));
      },
    );
    late _ManualTimer timer;
    final adapter = _createAdapter(
      detector,
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
    expect(detector.detectCalls, 1);

    timer
      ..fire()
      ..fire();
    await _flushMicrotasks();
    expect(detector.detectCalls, 1);

    await adapter.disable();
    firstDetection.complete(AppSuccess(_snapshot(1)));
    await _flushMicrotasks();

    expect(detections, isEmpty);
    expect(adapter.currentFrame.detections, isEmpty);

    await subscription.cancel();
    await adapter.close();
  });

  test('retries a failed model load without recreating the adapter', () async {
    final detector = _FakeRecordedFrameDetector(
      loadResults: Queue.of([
        const AppError<void>(NetworkFailure(code: 'model_download')),
        const AppSuccess<void>(null),
      ]),
    );
    final adapter = _createAdapter(detector);
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await _flushMicrotasks();
    expect(events.last, isA<ObservationInferenceFailed>());

    await adapter.retryModel();
    await _flushMicrotasks();

    expect(detector.loadCalls, 2);
    expect(events.last, isA<ObservationModelReady>());

    await subscription.cancel();
    await adapter.close();
  });

  test('waits for an in-flight model load before closing the detector', () async {
    final loadResult = Completer<AppResult<void>>();
    final detector = _FakeRecordedFrameDetector(
      onLoad: (_) => loadResult.future,
    );
    final adapter = _createAdapter(detector);

    await adapter.init();
    final closeFuture = adapter.close();
    await _flushMicrotasks();

    expect(detector.closeCalls, 0);

    loadResult.complete(const AppSuccess<void>(null));
    await closeFuture;

    expect(detector.closeCalls, 1);
  });

  test('waits for in-flight inference before closing the detector', () async {
    final detection = Completer<AppResult<ObservationSnapshot>>();
    final detector = _FakeRecordedFrameDetector(
      onDetect: (_, _) => detection.future,
    );
    final adapter = _createAdapter(detector);

    await adapter.init();
    await _flushMicrotasks();
    await adapter.enable(CameraLens.back);
    await _flushMicrotasks();

    final closeFuture = adapter.close();
    await _flushMicrotasks();
    expect(detector.closeCalls, 0);

    detection.complete(AppSuccess(_snapshot(1)));
    await closeFuture;
    expect(detector.closeCalls, 1);
  });

  test('keeps late model-download cancellation until load settles', () async {
    const modelId = 'yolo26n';
    final load = Completer<AppResult<void>>();
    final detector = _FakeRecordedFrameDetector(onLoad: (_) => load.future);
    final adapter = _createAdapter(detector);

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

  test('publishes read-only frame bytes', () async {
    final adapter = _createAdapter(_FakeRecordedFrameDetector());

    expect(
      () => adapter.currentFrame.encodedImage[0] = 0,
      throwsA(isA<UnsupportedError>()),
    );

    await adapter.close();
  });

  test('clears stale boxes and retries inference without reloading', () async {
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
    final timers = <_ManualTimer>[];
    final adapter = _createAdapter(
      detector,
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
    expect(adapter.currentFrame.detections, isNotEmpty);

    timers.single.fire();
    await _flushMicrotasks();
    expect(events.last, isA<ObservationFailed>());
    expect(adapter.currentFrame.detections, isEmpty);

    await adapter.retryObservation();
    await _flushMicrotasks();
    expect(detector.loadCalls, 1);
    expect(detector.detectCalls, 3);
    expect(adapter.currentFrame.detections.single.label, 'person');

    await subscription.cancel();
    await adapter.close();
  });
}

RecordedObservationAdapter _createAdapter(
  RecordedFrameDetector detector, {
  RecordedReplayTimerFactory? timerFactory,
}) {
  final fixture = recordedBusFixture();
  return RecordedObservationAdapter.withTimerFactory(
    detector,
    timerFactory ?? _unusedTimerFactory,
    frames: fixture.frames,
    frameWidth: fixture.frameWidth,
    frameHeight: fixture.frameHeight,
  );
}

Timer _unusedTimerFactory(Duration interval, void Function() onTick) {
  return _ManualTimer(onTick);
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

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
      Duration(milliseconds: frameNumber * 500),
    ),
  );
}
