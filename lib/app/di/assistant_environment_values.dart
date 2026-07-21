import 'package:pov_agent/core/constants/compilation_constants.dart';

/// Raw compile-time values consumed by assistant dependency composition.
///
/// The three groups mirror the independently acquired Qwen, Piper, and ASR
/// runtimes. Keeping raw strings here lets `AssistantBuildConfiguration`
/// reject malformed `--dart-define` values instead of accepting the silent
/// fallback behavior of typed `fromEnvironment` constructors.
final class AssistantEnvironmentValues {
  /// Creates the default environment view or injects one model group in tests.
  const AssistantEnvironmentValues({
    this.qwen = const QwenEnvironmentValues(),
    this.piper = const PiperEnvironmentValues(),
    this.asr = const AsrEnvironmentValues(),
  });

  /// Qwen artifact, native-runtime, prompt, and sampling values.
  final QwenEnvironmentValues qwen;

  /// Piper artifact, voice-runtime, and synthesis values.
  final PiperEnvironmentValues piper;

  /// Streaming-ASR artifact, runtime, endpoint, and wake-phrase values.
  final AsrEnvironmentValues asr;
}

/// Raw compile-time values for the local Qwen dialogue runtime.
final class QwenEnvironmentValues {
  /// Creates a Qwen environment group backed by the checked-in defaults.
  const QwenEnvironmentValues({
    this.modelId = CompilationConstants.qwenModelId,
    this.modelUrl = CompilationConstants.qwenModelUrl,
    this.modelRevision = CompilationConstants.qwenModelRevision,
    this.modelFilename = CompilationConstants.qwenModelFilename,
    this.modelSizeBytes = CompilationConstants.qwenModelSizeBytes,
    this.modelSha256 = CompilationConstants.qwenModelSha256,
    this.modelLicense = CompilationConstants.qwenModelLicense,
    this.downloadReserveBytes = CompilationConstants.qwenDownloadReserveBytes,
    this.contextTokens = CompilationConstants.qwenContextTokens,
    this.batchTokens = CompilationConstants.qwenBatchTokens,
    this.threadCount = CompilationConstants.qwenThreadCount,
    this.gpuLayers = CompilationConstants.qwenGpuLayers,
    this.randomSeed = CompilationConstants.qwenRandomSeed,
    this.systemPrompt = CompilationConstants.qwenSystemPrompt,
    this.dialogueMaxTokens = CompilationConstants.qwenManualMaxTokens,
    this.dialogueTemperature = CompilationConstants.qwenManualTemperature,
    this.dialogueTopP = CompilationConstants.qwenManualTopP,
    this.dialogueTopK = CompilationConstants.qwenManualTopK,
    this.dialogueMinP = CompilationConstants.qwenManualMinP,
    this.commentMaxTokens = CompilationConstants.qwenCommentMaxTokens,
    this.commentTemperature = CompilationConstants.qwenCommentTemperature,
    this.commentTopP = CompilationConstants.qwenCommentTopP,
    this.commentTopK = CompilationConstants.qwenCommentTopK,
    this.commentMinP = CompilationConstants.qwenCommentMinP,
  });

  /// Stable cache and diagnostic identity of the Qwen artifact.
  final String modelId;

  /// Pinned Qwen artifact URL.
  final String modelUrl;

  /// Immutable upstream Qwen revision.
  final String modelRevision;

  /// Published filename inside the shared model cache.
  final String modelFilename;

  /// Expected Qwen artifact length in bytes.
  final String modelSizeBytes;

  /// Expected lowercase SHA-256 of the Qwen artifact.
  final String modelSha256;

  /// License identifier recorded with the Qwen artifact.
  final String modelLicense;

  /// Free-space reserve required beyond the Qwen artifact.
  final String downloadReserveBytes;

  /// Maximum llama.cpp context size.
  final String contextTokens;

  /// Maximum llama.cpp prompt batch size.
  final String batchTokens;

  /// llama.cpp worker-thread count.
  final String threadCount;

  /// Requested Qwen GPU-offload layer count.
  final String gpuLayers;

  /// Base seed used by the Qwen sampler.
  final String randomSeed;

  /// Shared system instruction for local dialogue and comments.
  final String systemPrompt;

  /// Output-token limit for typed and hands-free dialogue.
  final String dialogueMaxTokens;

  /// Temperature for typed and hands-free dialogue.
  final String dialogueTemperature;

  /// Top-p threshold for typed and hands-free dialogue.
  final String dialogueTopP;

  /// Top-k threshold for typed and hands-free dialogue.
  final String dialogueTopK;

  /// Min-p threshold for typed and hands-free dialogue.
  final String dialogueMinP;

  /// Output-token limit for automatic scene comments.
  final String commentMaxTokens;

  /// Temperature for automatic scene comments.
  final String commentTemperature;

  /// Top-p threshold for automatic scene comments.
  final String commentTopP;

  /// Top-k threshold for automatic scene comments.
  final String commentTopK;

  /// Min-p threshold for automatic scene comments.
  final String commentMinP;
}

/// Raw compile-time values for the local Piper synthesis runtime.
final class PiperEnvironmentValues {
  /// Creates a Piper environment group backed by the checked-in defaults.
  const PiperEnvironmentValues({
    this.modelId = CompilationConstants.piperModelId,
    this.modelUrl = CompilationConstants.piperModelUrl,
    this.modelRevision = CompilationConstants.piperModelRevision,
    this.archiveFilename = CompilationConstants.piperModelArchiveFilename,
    this.archiveSizeBytes = CompilationConstants.piperModelArchiveSizeBytes,
    this.archiveSha256 = CompilationConstants.piperModelArchiveSha256,
    this.expandedArchiveSizeBytes = CompilationConstants.piperModelExpandedArchiveSizeBytes,
    this.extractedSizeBytes = CompilationConstants.piperModelExtractedSizeBytes,
    this.extractedFileCount = CompilationConstants.piperModelExtractedFileCount,
    this.bundleTreeSha256 = CompilationConstants.piperModelBundleTreeSha256,
    this.archiveRoot = CompilationConstants.piperModelArchiveRoot,
    this.modelFilename = CompilationConstants.piperModelFilename,
    this.tokensFilename = CompilationConstants.piperTokensFilename,
    this.espeakDataDirectory = CompilationConstants.piperEspeakDataDirectory,
    this.modelLicense = CompilationConstants.piperModelLicense,
    this.downloadReserveBytes = CompilationConstants.piperDownloadReserveBytes,
    this.provider = CompilationConstants.piperProvider,
    this.threadCount = CompilationConstants.piperThreadCount,
    this.speakerId = CompilationConstants.piperSpeakerId,
    this.noiseScale = CompilationConstants.piperNoiseScale,
    this.noiseScaleW = CompilationConstants.piperNoiseScaleW,
    this.lengthScale = CompilationConstants.piperLengthScale,
    this.speed = CompilationConstants.piperSpeed,
    this.silenceScale = CompilationConstants.piperSilenceScale,
    this.maxSentences = CompilationConstants.piperMaxSentences,
    this.debug = CompilationConstants.piperDebug,
  });

  /// Stable cache and diagnostic identity of the Piper bundle.
  final String modelId;

  /// Pinned Piper archive URL.
  final String modelUrl;

  /// Immutable upstream Piper release label.
  final String modelRevision;

  /// Published Piper archive filename.
  final String archiveFilename;

  /// Expected compressed archive length in bytes.
  final String archiveSizeBytes;

  /// Expected lowercase SHA-256 of the compressed archive.
  final String archiveSha256;

  /// Expected temporary tar length in bytes.
  final String expandedArchiveSizeBytes;

  /// Expected total length of extracted regular files.
  final String extractedSizeBytes;

  /// Expected number of extracted regular files.
  final String extractedFileCount;

  /// Expected digest of the canonical extracted file tree.
  final String bundleTreeSha256;

  /// Top-level directory published into the model cache.
  final String archiveRoot;

  /// Relative ONNX model filename inside the extracted bundle.
  final String modelFilename;

  /// Relative token-table filename inside the extracted bundle.
  final String tokensFilename;

  /// Relative eSpeak NG data directory inside the extracted bundle.
  final String espeakDataDirectory;

  /// License identifier recorded with the Piper voice.
  final String modelLicense;

  /// Free-space reserve required beyond all Piper staging files.
  final String downloadReserveBytes;

  /// sherpa-onnx execution provider.
  final String provider;

  /// Piper worker-thread count.
  final String threadCount;

  /// Selected Piper speaker index.
  final String speakerId;

  /// Piper synthesis noise scale.
  final String noiseScale;

  /// Piper synthesis phoneme-duration noise scale.
  final String noiseScaleW;

  /// Piper synthesis duration scale.
  final String lengthScale;

  /// User-facing Piper speaking-speed multiplier.
  final String speed;

  /// Silence-duration scale between Piper sentences.
  final String silenceScale;

  /// Maximum sentences synthesized in one native call.
  final String maxSentences;

  /// Whether sherpa-onnx emits native Piper diagnostics.
  final String debug;
}

/// Raw compile-time values for streaming recognition and wake detection.
final class AsrEnvironmentValues {
  /// Creates an ASR environment group backed by the checked-in defaults.
  const AsrEnvironmentValues({
    this.modelId = CompilationConstants.asrModelId,
    this.modelUrl = CompilationConstants.asrModelUrl,
    this.modelRevision = CompilationConstants.asrModelRevision,
    this.archiveFilename = CompilationConstants.asrModelArchiveFilename,
    this.archiveSizeBytes = CompilationConstants.asrModelArchiveSizeBytes,
    this.archiveSha256 = CompilationConstants.asrModelArchiveSha256,
    this.expandedArchiveSizeBytes = CompilationConstants.asrModelExpandedArchiveSizeBytes,
    this.extractedSizeBytes = CompilationConstants.asrModelExtractedSizeBytes,
    this.extractedFileCount = CompilationConstants.asrModelExtractedFileCount,
    this.bundleTreeSha256 = CompilationConstants.asrModelBundleTreeSha256,
    this.archiveRoot = CompilationConstants.asrModelArchiveRoot,
    this.modelFilename = CompilationConstants.asrModelFilename,
    this.tokensFilename = CompilationConstants.asrTokensFilename,
    this.modelLicense = CompilationConstants.asrModelLicense,
    this.downloadReserveBytes = CompilationConstants.asrDownloadReserveBytes,
    this.provider = CompilationConstants.asrProvider,
    this.threadCount = CompilationConstants.asrThreadCount,
    this.sampleRate = CompilationConstants.asrSampleRate,
    this.featureDimension = CompilationConstants.asrFeatureDimension,
    this.decodingMethod = CompilationConstants.asrDecodingMethod,
    this.maximumActivePaths = CompilationConstants.asrMaximumActivePaths,
    this.emptyTrailingSilenceSeconds = CompilationConstants.asrEmptyTrailingSilenceSeconds,
    this.trailingSilenceSeconds = CompilationConstants.asrTrailingSilenceSeconds,
    this.maximumUtteranceSeconds = CompilationConstants.asrMaximumUtteranceSeconds,
    this.wakePhrase = CompilationConstants.asrWakePhrase,
    this.maximumPendingAudioChunks = CompilationConstants.asrMaximumPendingAudioChunks,
    this.debug = CompilationConstants.asrDebug,
  });

  /// Stable cache and diagnostic identity of the ASR bundle.
  final String modelId;

  /// Pinned streaming-ASR archive URL.
  final String modelUrl;

  /// Immutable upstream ASR release label.
  final String modelRevision;

  /// Published ASR archive filename.
  final String archiveFilename;

  /// Expected compressed archive length in bytes.
  final String archiveSizeBytes;

  /// Expected lowercase SHA-256 of the compressed archive.
  final String archiveSha256;

  /// Expected temporary tar length in bytes.
  final String expandedArchiveSizeBytes;

  /// Expected total length of extracted regular files.
  final String extractedSizeBytes;

  /// Expected number of extracted regular files.
  final String extractedFileCount;

  /// Expected digest of the canonical extracted file tree.
  final String bundleTreeSha256;

  /// Top-level directory published into the model cache.
  final String archiveRoot;

  /// Relative streaming model filename inside the extracted bundle.
  final String modelFilename;

  /// Relative token-table filename inside the extracted bundle.
  final String tokensFilename;

  /// License identifier recorded with the ASR model.
  final String modelLicense;

  /// Free-space reserve required beyond all ASR staging files.
  final String downloadReserveBytes;

  /// sherpa-onnx execution provider.
  final String provider;

  /// Streaming recognizer worker-thread count.
  final String threadCount;

  /// Microphone and recognizer sample rate in hertz.
  final String sampleRate;

  /// Feature-extractor dimension required by the pinned model.
  final String featureDimension;

  /// Streaming CTC decoding algorithm.
  final String decodingMethod;

  /// Maximum active paths retained by the decoder.
  final String maximumActivePaths;

  /// Silence endpoint used before any speech is decoded.
  final String emptyTrailingSilenceSeconds;

  /// Silence endpoint used after speech is decoded.
  final String trailingSilenceSeconds;

  /// Hard upper bound for one recognized utterance.
  final String maximumUtteranceSeconds;

  /// Normalized English phrase that begins a voice turn.
  final String wakePhrase;

  /// Bounded audio chunks awaiting worker-isolate processing.
  final String maximumPendingAudioChunks;

  /// Whether sherpa-onnx emits native ASR diagnostics.
  final String debug;
}
