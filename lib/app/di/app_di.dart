import 'package:get_it/get_it.dart';
import 'package:meta/meta.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/assistant_build_configuration.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/data/adapters/flutter_tts_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_inference_worker.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_qwen_model_store.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/datasources/method_channel_recorded_video_frame_source.dart';
import 'package:pov_agent/features/camera/data/datasources/permission_handler_camera_permission_gateway.dart';
import 'package:pov_agent/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:pov_agent/features/camera/data/repositories/recorded_frame_detector_impl.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

/// The application composition container.
final GetIt appDependencies = GetIt.instance;

const _recordedVideoAssetPath = 'assets/video/pedestrians.mp4';

/// Composes and registers the runtime selected by [CompilationConstants].
AppRuntime configureDependencies() => _configureDependencies();

/// Composes production owners with an injectable model transport for tests.
@visibleForTesting
AppRuntime configureDependenciesForTesting({
  required ModelArtifactDownloader modelArtifactDownloader,
  SpeechSynthesizer? speechSynthesizer,
}) {
  return _configureDependencies(
    modelArtifactDownloader: modelArtifactDownloader,
    speechSynthesizer: speechSynthesizer,
  );
}

AppRuntime _configureDependencies({
  ModelArtifactDownloader? modelArtifactDownloader,
  SpeechSynthesizer? speechSynthesizer,
}) {
  final assistantConfiguration = AssistantBuildConfiguration.fromEnvironment();
  final controller = CompilationConstants.usesRecordedVideo
      ? _registerRecordedObservation()
      : _registerCameraObservation();
  final sceneSession = ObservationSceneSession(
    controller: controller,
    stabilizer: SceneStabilizer(),
  );
  final commentGenerator = LlamaCommentGenerator(
    createWorker: NativeLlamaInferenceWorker.spawn,
    runtimeConfiguration: assistantConfiguration.runtime,
    randomSeed: assistantConfiguration.randomSeed,
  );
  final modelStore = VerifiedQwenModelStore(
    manifest: assistantConfiguration.manifest,
    directoryProvider: const ApplicationSupportModelDirectoryProvider(),
    diskCapacityGateway: MethodChannelModelDiskCapacityGateway(),
    downloader: modelArtifactDownloader ?? HttpModelArtifactDownloader(),
    checksumVerifier: const IsolateModelChecksumVerifier(),
    commentGenerator: commentGenerator,
  );
  final systemSpeechSynthesizer =
      speechSynthesizer ??
      FlutterTtsSpeechSynthesizer(
        preferredLanguage: CompilationConstants.systemSpeechLanguage,
      );
  final observerBloc = ObserverBloc(
    sceneSource: sceneSession,
    modelStore: modelStore,
    commentGenerator: commentGenerator,
    speechSynthesizer: systemSpeechSynthesizer,
    requestBuilder: ObserverRequestBuilder(
      qwenPromptBuilder: QwenPromptBuilder(
        systemPrompt: assistantConfiguration.systemPrompt,
        manualOptions: assistantConfiguration.manualOptions,
        shortCommentOptions: assistantConfiguration.commentOptions,
      ),
    ),
  );
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(controller),
    sceneSession: sceneSession,
    observerBloc: observerBloc,
    modelStore: modelStore,
    commentGenerator: commentGenerator,
    speechSynthesizer: systemSpeechSynthesizer,
  );

  appDependencies
    ..registerSingleton<ObservationController>(controller)
    ..registerSingleton<SceneSource>(sceneSession)
    ..registerSingleton<CommentGenerator>(commentGenerator)
    ..registerSingleton<ModelStore>(modelStore)
    ..registerSingleton<SpeechSynthesizer>(systemSpeechSynthesizer)
    ..registerSingleton<ObserverBloc>(observerBloc)
    ..registerSingleton<AppRuntime>(runtime);
  return runtime;
}

YoloObservationAdapter _registerCameraObservation() {
  final observationAdapter = YoloObservationAdapter(
    cameraPermissionGateway: const PermissionHandlerCameraPermissionGateway(),
  );
  appDependencies.registerSingleton<YoloObservationAdapter>(
    observationAdapter,
  );
  return observationAdapter;
}

RecordedObservationAdapter _registerRecordedObservation() {
  final detector = RecordedFrameDetectorImpl(
    UltralyticsRecordedFrameInference(),
  );
  final observationAdapter = RecordedObservationAdapter(
    detector: detector,
    frameSource: MethodChannelRecordedVideoFrameSource(
      assetPath: _recordedVideoAssetPath,
    ),
  );
  appDependencies
    ..registerSingleton<RecordedObservationAdapter>(observationAdapter)
    ..registerSingleton<RecordedObservationFrameSource>(observationAdapter);
  return observationAdapter;
}
