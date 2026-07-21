part of 'observer_bloc.dart';

/// Inputs for scene-aware Qwen generation owned by [ObserverBloc].
///
/// Grouping these ports makes the generation boundary explicit at composition
/// sites without moving their lifecycle ownership out of the Bloc.
final class ObserverGenerationDependencies {
  /// Creates the scene and generation dependency group.
  const ObserverGenerationDependencies({
    required this.sceneSource,
    required this.qwenModelStore,
    required this.commentGenerator,
    required this.requestBuilder,
  });

  /// Latest stable scene and its change stream.
  final SceneSource sceneSource;

  /// Verified Qwen artifact lifecycle.
  final QwenModelStore qwenModelStore;

  /// Single-flight native text-generation boundary.
  final CommentGenerator commentGenerator;

  /// Scene and dialogue request policy.
  final ObserverRequestBuilder requestBuilder;
}

/// Inputs for hands-free recognition and audible output owned by [ObserverBloc].
///
/// The Bloc still owns ordering between ASR, generation, and TTS; this value
/// only names the ports and immutable policy needed to construct that owner.
final class ObserverVoiceDependencies {
  /// Creates the voice input and output dependency group.
  const ObserverVoiceDependencies({
    required this.asrModelStore,
    required this.microphonePermissionGateway,
    required this.speechRecognizer,
    required this.speechSynthesizer,
    required this.wakePhrase,
    required this.questionDeadline,
  });

  /// Verified streaming-ASR bundle lifecycle.
  final AsrModelStore asrModelStore;

  /// Foreground microphone permission boundary.
  final MicrophonePermissionGateway microphonePermissionGateway;

  /// Streaming microphone and native recognition boundary.
  final SpeechRecognizer speechRecognizer;

  /// Foreground speech output boundary.
  final SpeechSynthesizer speechSynthesizer;

  /// Normalized phrase that begins one voice turn.
  final String wakePhrase;

  /// Hard wall-clock limit for collecting one voice question.
  final Duration questionDeadline;
}
