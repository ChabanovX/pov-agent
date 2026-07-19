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
      ModelLoadingException('Model download failed.'),
      StackTrace.empty,
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
