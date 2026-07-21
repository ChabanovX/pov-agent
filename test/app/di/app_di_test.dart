import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/di/app_di.dart';
import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/ports/comment_generator.dart';
import 'package:pov_agent/features/assistant/application/ports/microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_recognizer.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/fallback_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/just_audio_generated_speech_player.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/sherpa_online_speech_recognizer.dart';
import 'package:pov_agent/features/assistant/data/datasources/asset_pcm16_audio_source.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/permission_handler_microphone_permission_gateway.dart';
import 'package:pov_agent/features/assistant/data/datasources/record_microphone_audio_source.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_asr_model_store.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_piper_model_store.dart';
import 'package:pov_agent/features/assistant/presentation/bloc/observer_bloc.dart';
import 'package:pov_agent/features/camera/application/ports/observation_controller.dart';
import 'package:pov_agent/features/camera/application/ports/recorded_observation_frame_source.dart';
import 'package:pov_agent/features/camera/data/adapters/recorded_observation_adapter.dart';
import 'package:pov_agent/features/camera/data/adapters/yolo_observation_adapter.dart';
import 'package:pov_agent/shared/domain/app_result.dart';
import 'package:pov_agent/shared/domain/scene_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await appDependencies.reset(dispose: false);
  });

  test('registers the selected adapter under its surface contracts', () async {
    final runtime = configureDependenciesForTesting(
      modelArtifactDownloader: const _UnexpectedModelArtifactDownloader(),
      microphoneAudioSource: RecordMicrophoneAudioSource(
        backend: _NoopMicrophoneRecorderBackend(),
      ),
    );
    try {
      final controller = appDependencies<ObservationController>();
      expect(
        appDependencies<SceneSource>(),
        same(runtime.sceneSession),
      );
      expect(
        appDependencies<ObserverBloc>(),
        same(runtime.observerBloc),
      );
      expect(
        appDependencies<QwenModelStore>(),
        same(runtime.modelStore),
      );
      expect(
        appDependencies<AsrModelStore>(),
        same(runtime.asrModelStore),
      );
      expect(
        appDependencies<CommentGenerator>(),
        same(runtime.commentGenerator),
      );
      expect(
        appDependencies<SpeechRecognizer>(),
        same(runtime.speechRecognizer),
      );
      expect(
        appDependencies<SpeechSynthesizer>(),
        same(runtime.speechSynthesizer),
      );
      expect(
        runtime.speechSynthesizer,
        same(appDependencies<FallbackSpeechSynthesizer>()),
      );
      expect(
        appDependencies<PiperSpeechSynthesizer>().modelStore,
        same(appDependencies<VerifiedPiperModelStore>()),
      );
      expect(
        appDependencies<AsrModelStore>(),
        same(appDependencies<VerifiedAsrModelStore>()),
      );
      if (CompilationConstants.usesRecordedAudio) {
        expect(
          appDependencies.isRegistered<PermissionHandlerMicrophonePermissionGateway>(),
          isFalse,
        );
      } else {
        expect(
          appDependencies<MicrophonePermissionGateway>(),
          same(appDependencies<PermissionHandlerMicrophonePermissionGateway>()),
        );
      }
      expect(
        appDependencies<SpeechRecognizer>(),
        same(appDependencies<SherpaOnlineSpeechRecognizer>()),
      );
      expect(
        appDependencies<MicrophoneAudioSource>(),
        isA<RecordMicrophoneAudioSource>(),
      );
      expect(
        appDependencies<JustAudioGeneratedSpeechPlayer>().playbackProbe.isPlaying,
        isFalse,
      );
      expect(runtime.observerBloc.state.started, isFalse);
      expect(runtime.modelStore.current.phase, ModelStorePhase.idle);

      if (CompilationConstants.usesRecordedVideo) {
        final adapter = appDependencies<RecordedObservationAdapter>();
        expect(controller, same(adapter));
        expect(
          appDependencies<RecordedObservationFrameSource>(),
          same(adapter),
        );
        expect(
          appDependencies.isRegistered<YoloObservationAdapter>(),
          isFalse,
        );
      } else {
        final adapter = appDependencies<YoloObservationAdapter>();
        expect(controller, same(adapter));
        expect(
          appDependencies.isRegistered<RecordedObservationAdapter>(),
          isFalse,
        );
        expect(
          appDependencies.isRegistered<RecordedObservationFrameSource>(),
          isFalse,
        );
      }
    } finally {
      await runtime.close();
    }
  });

  test('selects the bundled PCM source for recorded-audio builds', () async {
    if (!CompilationConstants.usesRecordedAudio) return;

    final runtime = configureDependenciesForTesting(
      modelArtifactDownloader: const _UnexpectedModelArtifactDownloader(),
    );
    try {
      expect(
        appDependencies<MicrophoneAudioSource>(),
        isA<AssetPcm16AudioSource>(),
      );
      expect(
        appDependencies.isRegistered<PermissionHandlerMicrophonePermissionGateway>(),
        isFalse,
      );
      expect(
        await appDependencies<MicrophonePermissionGateway>().request(),
        isA<AppSuccess<void>>(),
      );
    } finally {
      await runtime.close();
    }
  });
}

final class _UnexpectedModelArtifactDownloader implements ModelArtifactDownloader {
  const _UnexpectedModelArtifactDownloader();

  @override
  Future<void> download({
    required Uri source,
    required String destinationPath,
    required int expectedBytes,
    required ModelDownloadProgress onProgress,
    required ModelDownloadCancellation cancellation,
  }) {
    throw StateError('Composition must not start model acquisition.');
  }
}

final class _NoopMicrophoneRecorderBackend implements MicrophoneRecorderBackend {
  @override
  Future<void> close() async {}

  @override
  Future<bool> supportsPcm16Stream() async => true;

  @override
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRateHz,
    required int streamBufferBytes,
  }) async => const Stream.empty();

  @override
  Future<void> stop() async {}
}
