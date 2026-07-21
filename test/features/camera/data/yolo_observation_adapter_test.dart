import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/observation_event.dart';
import 'package:pov_agent/features/camera/application/ports/camera_permission_gateway.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_capabilities.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:ultralytics_yolo/core/yolo_model_manager.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('close cancels an active model download', () async {
    const modelId = 'yolo26n';
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    await adapter.init();

    var cancelled = false;
    final token = YOLOModelManager.registerDownload(
      modelId,
      () => cancelled = true,
    );
    try {
      await adapter.close();
      expect(cancelled, isTrue);
    } finally {
      YOLOModelManager.finishDownload(modelId, token);
      YOLOModelManager.clearDownloadCancellation(modelId);
    }
  });

  test('failed download close does not poison the next model download', () async {
    const modelId = 'yolo26n';
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    await adapter.init();

    final downloadEvent = adapter.events.firstWhere(
      (event) => event is ObservationModelDownloadProgressed,
    );
    YOLOModelManager.emitProgress(modelId, 0);
    await downloadEvent;

    adapter.handleModelError(
      revision: adapter.surfaceRevision.value,
      error: ModelLoadingException('Model download failed.'),
      stackTrace: StackTrace.empty,
    );
    await adapter.close();

    var cancelled = false;
    final token = YOLOModelManager.registerDownload(
      modelId,
      () => cancelled = true,
    );
    try {
      expect(cancelled, isFalse);
    } finally {
      YOLOModelManager.finishDownload(modelId, token);
      YOLOModelManager.clearDownloadCancellation(modelId);
    }
  });

  test('accepts model load only from the current surface revision', () async {
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await adapter.enable(CameraLens.back);
    final staleRevision = adapter.surfaceRevision.value;
    await adapter.retryModel();

    adapter.handleModelLoaded(
      revision: staleRevision,
      attachedLens: CameraLens.back,
      modelPath: adapter.configuration.modelPath,
    );
    await pumpEventQueue();
    expect(events.whereType<ObservationModelReady>(), isEmpty);

    adapter.handleModelLoaded(
      revision: adapter.surfaceRevision.value,
      attachedLens: CameraLens.back,
      modelPath: adapter.configuration.modelPath,
    );
    await pumpEventQueue();
    expect(events.whereType<ObservationModelReady>(), hasLength(1));

    await subscription.cancel();
    await adapter.close();
  });

  test('lets a newly attached native surface own its initial camera start', () async {
    const channel = MethodChannel('test/yolo_initial_camera_start');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    addTearDown(adapter.close);

    await adapter.init();
    await adapter.enable(CameraLens.back);
    adapter.viewController.init(channel, 7);
    await pumpEventQueue();
    calls.clear();

    adapter.handleModelLoaded(
      revision: adapter.surfaceRevision.value,
      attachedLens: CameraLens.back,
      modelPath: adapter.configuration.modelPath,
    );
    await pumpEventQueue();

    expect(calls, isEmpty);
  });

  test('rejects observation callbacks from a superseded retry revision', () async {
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    await adapter.enable(CameraLens.back);
    final staleRevision = adapter.surfaceRevision.value;
    adapter.handleModelLoaded(
      revision: staleRevision,
      attachedLens: CameraLens.back,
      modelPath: adapter.configuration.modelPath,
    );
    await pumpEventQueue();
    events.clear();

    await adapter.retryModel();
    adapter
      ..handleResults(
        revision: staleRevision,
        results: const <YOLOResult>[],
      )
      ..handlePerformance(
        revision: staleRevision,
        performance: YOLOPerformanceMetrics(
          fps: 24,
          processingTimeMs: 41,
          frameNumber: 8,
          timestamp: DateTime.utc(2026, 7, 19),
        ),
      )
      ..handleModelError(
        revision: staleRevision,
        error: StateError('stale model error'),
        stackTrace: StackTrace.empty,
      );
    await pumpEventQueue();

    expect(events.whereType<ObservationModelPreparing>(), hasLength(1));
    expect(events.whereType<ObservationDetectionsUpdated>(), isEmpty);
    expect(events.whereType<ObservationDiagnosticsUpdated>(), isEmpty);
    expect(events.whereType<ObservationFailed>(), isEmpty);

    final currentRevision = adapter.surfaceRevision.value;
    adapter
      ..handleModelLoaded(
        revision: currentRevision,
        attachedLens: CameraLens.back,
        modelPath: adapter.configuration.modelPath,
      )
      ..handleResults(
        revision: currentRevision,
        results: const <YOLOResult>[],
      );
    await pumpEventQueue();
    expect(events.whereType<ObservationModelReady>(), hasLength(1));
    expect(events.whereType<ObservationDetectionsUpdated>(), hasLength(1));

    await subscription.cancel();
    await adapter.close();
  });

  test('suppresses callbacks while disabled and resumes the current revision', () async {
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    final revision = adapter.surfaceRevision.value;
    adapter.handleModelLoaded(
      revision: revision,
      attachedLens: CameraLens.back,
      modelPath: adapter.configuration.modelPath,
    );
    await pumpEventQueue();
    events.clear();

    adapter.handleResults(
      revision: revision,
      results: const <YOLOResult>[],
    );
    await pumpEventQueue();
    expect(events.whereType<ObservationDetectionsUpdated>(), isEmpty);

    await adapter.enable(CameraLens.back);
    adapter.handleResults(
      revision: revision,
      results: const <YOLOResult>[],
    );
    await pumpEventQueue();
    expect(events.whereType<ObservationDetectionsUpdated>(), hasLength(1));

    await adapter.disable();
    adapter.handleResults(
      revision: revision,
      results: const <YOLOResult>[],
    );
    await pumpEventQueue();
    expect(events.whereType<ObservationDetectionsUpdated>(), hasLength(1));

    await subscription.cancel();
    await adapter.close();
  });

  test('invalidates scene continuity when the desired lens changes', () async {
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(),
    );
    final events = <ObservationEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.init();
    final backRevision = adapter.surfaceRevision.value;
    adapter.handleModelLoaded(
      revision: backRevision,
      attachedLens: CameraLens.back,
      modelPath: adapter.configuration.modelPath,
    );
    await pumpEventQueue();
    events.clear();

    await adapter.enable(CameraLens.front);
    await pumpEventQueue();

    expect(adapter.surfaceRevision.value, greaterThan(backRevision));
    expect(events.whereType<ObservationSourceDiscontinuity>(), hasLength(1));

    adapter.handleResults(
      revision: backRevision,
      results: const <YOLOResult>[],
    );
    await pumpEventQueue();
    expect(events.whereType<ObservationDetectionsUpdated>(), isEmpty);

    final frontRevision = adapter.surfaceRevision.value;
    adapter
      ..handleModelLoaded(
        revision: frontRevision,
        attachedLens: CameraLens.front,
        modelPath: adapter.configuration.modelPath,
      )
      ..handleResults(
        revision: frontRevision,
        results: const <YOLOResult>[],
      );
    await pumpEventQueue();
    expect(events.whereType<ObservationDetectionsUpdated>(), hasLength(1));

    await subscription.cancel();
    await adapter.close();
  });

  test('denied camera permission prevents the native surface from starting', () async {
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: const _FakeCameraPermissionGateway(
        AppError<void>(PermissionDeniedFailure()),
      ),
    );

    final result = await adapter.init();

    expect(result, isA<AppError<CameraCapabilities>>());
    expect(
      (result as AppError<CameraCapabilities>).failure,
      isA<PermissionDeniedFailure>(),
    );
    await adapter.close();
  });

  test('enable detects permission revoked while the app was paused', () async {
    final permissionGateway = _SequenceCameraPermissionGateway([
      const AppSuccess<void>(null),
      const AppError<void>(PermissionDeniedFailure()),
    ]);
    final adapter = YoloObservationAdapter(
      cameraPermissionGateway: permissionGateway,
    );
    expect(await adapter.init(), isA<AppSuccess<CameraCapabilities>>());

    final result = await adapter.enable(CameraLens.back);

    expect(result, isA<AppError<void>>());
    expect((result as AppError<void>).failure, isA<PermissionDeniedFailure>());
    expect(permissionGateway.requestCalls, 2);
    await adapter.close();
  });
}

final class _FakeCameraPermissionGateway implements CameraPermissionGateway {
  const _FakeCameraPermissionGateway([
    this.result = const AppSuccess<void>(null),
  ]);

  final AppResult<void> result;

  @override
  Future<AppResult<void>> request() async => result;
}

final class _SequenceCameraPermissionGateway implements CameraPermissionGateway {
  _SequenceCameraPermissionGateway(this._results)
    : assert(
        _results.isNotEmpty,
        'A permission response sequence must not be empty.',
      );

  final List<AppResult<void>> _results;
  int requestCalls = 0;

  @override
  Future<AppResult<void>> request() async {
    final index = requestCalls < _results.length ? requestCalls : _results.length - 1;
    final result = _results[index];
    requestCalls += 1;
    return result;
  }
}
