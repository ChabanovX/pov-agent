import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/camera/application/models/observation_configuration.dart';
import 'package:pov_agent/features/camera/domain/entities/camera_lens.dart';
import 'package:pov_agent/features/camera/presentation/widgets/yolo_observation_surface.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  testWidgets('wires composed YOLO dependencies into each surface revision', (
    tester,
  ) async {
    const configuration = ObservationConfiguration(
      modelPath: 'test-model',
      cameraResolution: '1080p',
      confidenceThreshold: 0.55,
      iouThreshold: 0.65,
      useGpu: false,
    );
    final surfaceRevision = ValueNotifier(4);
    final viewController = YOLOViewController();
    addTearDown(surfaceRevision.dispose);
    addTearDown(viewController.dispose);

    var desiredLens = CameraLens.front;
    List<YOLOResult>? receivedResults;
    YOLOPerformanceMetrics? receivedPerformance;
    (int, CameraLens, String)? receivedModelLoad;
    Object? receivedModelError;
    StackTrace? receivedModelErrorStackTrace;
    final surface = YoloObservationSurface(
      configuration: configuration,
      surfaceRevision: surfaceRevision,
      desiredLens: () => desiredLens,
      viewController: viewController,
      onResults: (results) => receivedResults = results,
      onPerformance: (performance) => receivedPerformance = performance,
      onModelLoaded:
          ({
            required revision,
            required attachedLens,
            required modelPath,
          }) {
            receivedModelLoad = (revision, attachedLens, modelPath);
          },
      onModelError: (error, stackTrace) {
        receivedModelError = error;
        receivedModelErrorStackTrace = stackTrace;
      },
    );

    late BuildContext buildContext;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            buildContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final revisionBuilder = surface.build(buildContext) as ValueListenableBuilder<int>;
    final yoloView =
        revisionBuilder.builder(
              buildContext,
              surfaceRevision.value,
              null,
            )
            as YOLOView;

    expect(yoloView.key, const ValueKey(('yolo-observation-surface', 4)));
    expect(yoloView.modelPath, configuration.modelPath);
    expect(yoloView.task, YOLOTask.detect);
    expect(yoloView.controller, same(viewController));
    expect(yoloView.cameraResolution, configuration.cameraResolution);
    expect(yoloView.confidenceThreshold, configuration.confidenceThreshold);
    expect(yoloView.iouThreshold, configuration.iouThreshold);
    expect(yoloView.useGpu, configuration.useGpu);
    expect(yoloView.lensFacing, LensFacing.front);

    final results = <YOLOResult>[];
    final performance = YOLOPerformanceMetrics(
      fps: 24,
      processingTimeMs: 41,
      frameNumber: 8,
      timestamp: DateTime.utc(2026, 7, 19),
    );
    final modelError = StateError('model failed');
    yoloView.onResult!(results);
    yoloView.onPerformanceMetrics!(performance);
    yoloView.onModelLoad!('test-model', YOLOTask.detect);
    yoloView.onModelError!(modelError, 'test-model', YOLOTask.detect);

    expect(receivedResults, same(results));
    expect(receivedPerformance, same(performance));
    expect(receivedModelLoad, (4, CameraLens.front, 'test-model'));
    expect(receivedModelError, same(modelError));
    expect(receivedModelErrorStackTrace, isNotNull);

    desiredLens = CameraLens.back;
    final rebuiltYoloView =
        revisionBuilder.builder(
              buildContext,
              5,
              null,
            )
            as YOLOView;
    expect(
      rebuiltYoloView.key,
      const ValueKey(('yolo-observation-surface', 5)),
    );
    expect(rebuiltYoloView.lensFacing, LensFacing.back);
  });
}
