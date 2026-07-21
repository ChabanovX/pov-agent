import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:pov_agent/app/bootstrap/app_runtime.dart';
import 'package:pov_agent/app/di/assistant_build_configuration.dart';
import 'package:pov_agent/app/di/file_model_pack_receipt_store.dart';
import 'package:pov_agent/app/model_pack/model_pack_controller.dart';
import 'package:pov_agent/app/model_pack/model_pack_receipt_store.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/application/services/observer_request_builder.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_prompt_builder.dart';
import 'package:pov_agent/features/assistant/data/adapters/fallback_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/flutter_tts_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/just_audio_generated_speech_player.dart';
import 'package:pov_agent/features/assistant/data/adapters/llama_comment_generator.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/sherpa_online_speech_recognizer.dart';
import 'package:pov_agent/features/assistant/data/datasources/asset_pcm16_audio_source.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/datasources/permission_handler_microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/platform_model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/record_microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_inference_worker.dart';
import 'package:pov_agent/features/assistant/data/ffi/sherpa_piper_speech_generator.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_asr_model_store.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_piper_model_store.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_qwen_model_store.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/camera/application/models/vision_model_manifest.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/application/ports/vision_model_verifier.dart';
import 'package:pov_agent/features/camera/application/services/observation_scene_session.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/datasources/method_channel_recorded_video_frame_source.dart';
import 'package:pov_agent/features/camera/data/datasources/permission_handler_camera_permission_gateway.dart';
import 'package:pov_agent/features/camera/data/datasources/recorded_frame_inference.dart';
import 'package:pov_agent/features/camera/data/repositories/bundled_vision_model_verifier.dart';
import 'package:pov_agent/features/camera/data/repositories/recorded_frame_detector_impl.dart';
import 'package:pov_agent/features/camera/domain/services/scene_stabilizer.dart';
import 'package:pov_agent/features/camera/presentation/bloc/camera_bloc.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

/// The application composition container.
final GetIt appDependencies = GetIt.instance;

const _recordedVideoAssetPath = 'assets/video/pedestrians.mp4';
const _recordedAudioAssetPath = 'assets/audio/hands_free_question_en_us.pcm';

/// Composes and registers the runtime selected by [CompilationConstants].
AppRuntime configureDependencies() => _configureDependencies();

/// Composes production owners with injectable native boundaries for tests.
@visibleForTesting
AppRuntime configureDependenciesForTesting({
  required ModelArtifactDownloader modelArtifactDownloader,
  ModelArtifactDownloader? piperModelArtifactDownloader,
  ModelArtifactDownloader? asrModelArtifactDownloader,
  MicrophonePermissionGateway? microphonePermissionGateway,
  MicrophoneAudioSource? microphoneAudioSource,
  SpeechRecognizer? speechRecognizer,
  SpeechSynthesizer? speechSynthesizer,
}) {
  return _configureDependencies(
    modelArtifactDownloader: modelArtifactDownloader,
    piperModelArtifactDownloader: piperModelArtifactDownloader,
    asrModelArtifactDownloader: asrModelArtifactDownloader,
    microphonePermissionGateway: microphonePermissionGateway,
    microphoneAudioSource: microphoneAudioSource,
    speechRecognizer: speechRecognizer,
    speechSynthesizer: speechSynthesizer,
  );
}

AppRuntime _configureDependencies({
  ModelArtifactDownloader? modelArtifactDownloader,
  ModelArtifactDownloader? piperModelArtifactDownloader,
  ModelArtifactDownloader? asrModelArtifactDownloader,
  MicrophonePermissionGateway? microphonePermissionGateway,
  MicrophoneAudioSource? microphoneAudioSource,
  SpeechRecognizer? speechRecognizer,
  SpeechSynthesizer? speechSynthesizer,
}) {
  final assistantConfiguration = AssistantBuildConfiguration.fromEnvironment();
  final modelDirectoryProvider = PlatformModelDirectoryProvider();
  final modelDiskCapacityGateway = MethodChannelModelDiskCapacityGateway();
  final defaultModelArtifactDownloader = modelArtifactDownloader ?? createPlatformModelArtifactDownloader();
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
    directoryProvider: modelDirectoryProvider,
    diskCapacityGateway: modelDiskCapacityGateway,
    downloader: defaultModelArtifactDownloader,
    checksumVerifier: const IsolateModelChecksumVerifier(),
  );
  final visionManifest = bundledVisionManifestFor(defaultTargetPlatform);
  final visionVerifier = BundledVisionModelVerifier(
    assetBundle: rootBundle,
    manifest: visionManifest,
  );
  final piperModelStore = _registerPiperModelStore(
    configuration: assistantConfiguration,
    directoryProvider: modelDirectoryProvider,
    diskCapacityGateway: modelDiskCapacityGateway,
    modelArtifactDownloader: piperModelArtifactDownloader ?? defaultModelArtifactDownloader,
  );
  final effectiveSpeechSynthesizer =
      speechSynthesizer ??
      _registerLocalSpeech(
        configuration: assistantConfiguration,
        modelStore: piperModelStore,
      );
  final voiceInput = _registerVoiceInput(
    configuration: assistantConfiguration,
    directoryProvider: modelDirectoryProvider,
    diskCapacityGateway: modelDiskCapacityGateway,
    modelArtifactDownloader: asrModelArtifactDownloader ?? defaultModelArtifactDownloader,
    microphonePermissionGateway: microphonePermissionGateway,
    microphoneAudioSource: microphoneAudioSource,
    speechRecognizer: speechRecognizer,
  );
  final receiptStore = FileModelPackReceiptStore(modelDirectoryProvider);
  final modelPackController = ModelPackController(
    qwenStore: modelStore,
    visionVerifier: visionVerifier,
    piperStore: piperModelStore,
    asrStore: voiceInput.modelStore,
    receiptStore: receiptStore,
    capacityReader: () async {
      final directory = await modelDirectoryProvider.resolve();
      await directory.create(recursive: true);
      return modelDiskCapacityGateway.availableBytes(directory.path);
    },
    fingerprint: _modelPackFingerprint(
      assistantConfiguration,
      visionManifest,
    ),
    qwenDownloadBytes: assistantConfiguration.manifest.byteSize,
    piperDownloadBytes: assistantConfiguration.piperManifest.archiveByteSize,
    asrDownloadBytes: assistantConfiguration.asrManifest.archiveByteSize,
  );
  final observerBloc = ObserverBloc(
    generation: ObserverGenerationDependencies(
      sceneSource: sceneSession,
      qwenModelStore: modelStore,
      commentGenerator: commentGenerator,
      requestBuilder: ObserverRequestBuilder(
        qwenPromptBuilder: QwenPromptBuilder(
          systemPrompt: assistantConfiguration.systemPrompt,
          dialogueOptions: assistantConfiguration.dialogueOptions,
          shortCommentOptions: assistantConfiguration.commentOptions,
        ),
      ),
    ),
    voice: ObserverVoiceDependencies(
      asrModelStore: voiceInput.modelStore,
      microphonePermissionGateway: voiceInput.permissionGateway,
      speechRecognizer: voiceInput.speechRecognizer,
      speechSynthesizer: effectiveSpeechSynthesizer,
      wakePhrase: assistantConfiguration.asrWakePhrase,
      questionDeadline: assistantConfiguration.asrRuntime.maxUtteranceDuration,
    ),
  );
  final runtime = AppRuntime(
    cameraBloc: CameraBloc(
      controller,
      initiallyRequestedEnabled: false,
    ),
    sceneSession: sceneSession,
    observerBloc: observerBloc,
    modelStore: modelStore,
    asrModelStore: voiceInput.modelStore,
    commentGenerator: commentGenerator,
    speechRecognizer: voiceInput.speechRecognizer,
    speechSynthesizer: effectiveSpeechSynthesizer,
    modelPackController: modelPackController,
    standalonePiperModelStore: speechSynthesizer == null ? null : piperModelStore,
  );

  appDependencies
    ..registerSingleton<ObservationController>(controller)
    ..registerSingleton<SceneSource>(sceneSession)
    ..registerSingleton<CommentGenerator>(commentGenerator)
    ..registerSingleton<QwenModelStore>(modelStore)
    ..registerSingleton<VisionModelVerifier>(visionVerifier)
    ..registerSingleton<AsrModelStore>(voiceInput.modelStore)
    ..registerSingleton<MicrophonePermissionGateway>(voiceInput.permissionGateway)
    ..registerSingleton<SpeechRecognizer>(voiceInput.speechRecognizer)
    ..registerSingleton<SpeechSynthesizer>(effectiveSpeechSynthesizer)
    ..registerSingleton<ObserverBloc>(observerBloc)
    ..registerSingleton<ModelPackReceiptStore>(receiptStore)
    ..registerSingleton<ModelPackController>(modelPackController)
    ..registerSingleton<AppRuntime>(runtime);
  return runtime;
}

({
  VerifiedAsrModelStore modelStore,
  MicrophonePermissionGateway permissionGateway,
  SpeechRecognizer speechRecognizer,
})
_registerVoiceInput({
  required AssistantBuildConfiguration configuration,
  required ModelDirectoryProvider directoryProvider,
  required ModelDiskCapacityGateway diskCapacityGateway,
  required ModelArtifactDownloader modelArtifactDownloader,
  MicrophonePermissionGateway? microphonePermissionGateway,
  MicrophoneAudioSource? microphoneAudioSource,
  SpeechRecognizer? speechRecognizer,
}) {
  final modelStore = VerifiedAsrModelStore(
    manifest: configuration.asrManifest,
    directoryProvider: directoryProvider,
    diskCapacityGateway: diskCapacityGateway,
    downloader: modelArtifactDownloader,
    checksumVerifier: const IsolateModelChecksumVerifier(),
    bundleExtractor: const IsolateModelBundleExtractor(),
    bundleVerifier: const IsolateModelBundleVerifier(),
  );
  final permissionGateway =
      microphonePermissionGateway ??
      (CompilationConstants.usesRecordedAudio
          ? const _GrantedMicrophonePermissionGateway()
          : PermissionHandlerMicrophonePermissionGateway());
  final MicrophoneAudioSource? effectiveAudioSource;
  final SpeechRecognizer effectiveRecognizer;
  if (speechRecognizer == null) {
    effectiveAudioSource = microphoneAudioSource ?? _productionMicrophoneAudioSource(configuration);
    effectiveRecognizer = SherpaOnlineSpeechRecognizer(
      audioSource: effectiveAudioSource,
      configuration: configuration.asrRuntime,
    );
  } else {
    effectiveAudioSource = null;
    effectiveRecognizer = speechRecognizer;
  }

  appDependencies.registerSingleton<VerifiedAsrModelStore>(modelStore);
  if (permissionGateway is PermissionHandlerMicrophonePermissionGateway) {
    appDependencies.registerSingleton<PermissionHandlerMicrophonePermissionGateway>(
      permissionGateway,
    );
  }
  if (effectiveRecognizer is SherpaOnlineSpeechRecognizer) {
    appDependencies.registerSingleton<SherpaOnlineSpeechRecognizer>(
      effectiveRecognizer,
    );
  }
  if (effectiveAudioSource != null) {
    appDependencies.registerSingleton<MicrophoneAudioSource>(
      effectiveAudioSource,
    );
  }
  return (
    modelStore: modelStore,
    permissionGateway: permissionGateway,
    speechRecognizer: effectiveRecognizer,
  );
}

MicrophoneAudioSource _productionMicrophoneAudioSource(
  AssistantBuildConfiguration configuration,
) {
  if (CompilationConstants.usesRecordedAudio) {
    return AssetPcm16AudioSource(
      assetBundle: rootBundle,
      assetPath: _recordedAudioAssetPath,
      sampleRateHz: configuration.asrRuntime.sampleRateHz,
    );
  }
  return RecordMicrophoneAudioSource();
}

final class _GrantedMicrophonePermissionGateway implements MicrophonePermissionGateway {
  const _GrantedMicrophonePermissionGateway();

  @override
  Future<AppResult<void>> openApplicationSettings() {
    return Future.value(const AppSuccess<void>(null));
  }

  @override
  Future<AppResult<void>> request() {
    return Future.value(const AppSuccess<void>(null));
  }
}

VerifiedPiperModelStore _registerPiperModelStore({
  required AssistantBuildConfiguration configuration,
  required ModelDirectoryProvider directoryProvider,
  required ModelDiskCapacityGateway diskCapacityGateway,
  required ModelArtifactDownloader modelArtifactDownloader,
}) {
  final modelStore = VerifiedPiperModelStore(
    manifest: configuration.piperManifest,
    directoryProvider: directoryProvider,
    diskCapacityGateway: diskCapacityGateway,
    downloader: modelArtifactDownloader,
    checksumVerifier: const IsolateModelChecksumVerifier(),
    bundleExtractor: const IsolatePiperBundleExtractor(),
    bundleVerifier: const IsolatePiperBundleVerifier(),
  );
  appDependencies.registerSingleton<VerifiedPiperModelStore>(modelStore);
  return modelStore;
}

FallbackSpeechSynthesizer _registerLocalSpeech({
  required AssistantBuildConfiguration configuration,
  required VerifiedPiperModelStore modelStore,
}) {
  final audioPlayer = JustAudioGeneratedSpeechPlayer();
  final piper = PiperSpeechSynthesizer(
    modelStore: modelStore,
    generator: const SherpaPiperSpeechGenerator(),
    audioPlayer: audioPlayer,
    configuration: configuration.piperRuntime,
  );
  final systemFallback = FlutterTtsSpeechSynthesizer(
    preferredLanguage: CompilationConstants.systemSpeechLanguage,
  );
  final coordinator = FallbackSpeechSynthesizer(
    primary: piper,
    fallback: systemFallback,
    shouldFallback: isPiperFallbackEligible,
  );

  appDependencies
    ..registerSingleton<PiperSpeechSynthesizer>(piper)
    ..registerSingleton<JustAudioGeneratedSpeechPlayer>(audioPlayer)
    ..registerSingleton<FallbackSpeechSynthesizer>(coordinator);
  return coordinator;
}

String _modelPackFingerprint(
  AssistantBuildConfiguration configuration,
  VisionModelManifest vision,
) {
  final qwen = configuration.manifest;
  final piper = configuration.piperManifest;
  final asr = configuration.asrManifest;
  return [
    'model-pack-v2',
    qwen.modelId,
    qwen.revision,
    qwen.sha256,
    vision.modelId,
    vision.revision,
    vision.assetPath,
    vision.byteSize,
    vision.sha256,
    piper.modelId,
    piper.revision,
    piper.archiveSha256,
    piper.bundleTreeSha256,
    asr.modelId,
    asr.revision,
    asr.archiveSha256,
    asr.bundleTreeSha256,
  ].join('|');
}

YoloObservationAdapter _registerCameraObservation() {
  final observationAdapter = YoloObservationAdapter(
    cameraPermissionGateway: PermissionHandlerCameraPermissionGateway(),
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
