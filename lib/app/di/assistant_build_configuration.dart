import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/application/models/piper_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_native_runtime.dart';
import 'package:pov_agent/features/assistant/data/models/piper_model_manifest.dart';
import 'package:pov_agent/features/assistant/data/models/qwen_model_manifest.dart';

/// Validated assistant policy assembled from compile-time environment values.
///
/// Numeric defines enter as strings and are parsed once at the composition
/// root. This avoids `int.fromEnvironment` silently replacing malformed input
/// with a default. Invalid combinations fail during bootstrap instead of
/// reaching model acquisition or native FFI.
final class AssistantBuildConfiguration {
  AssistantBuildConfiguration._({
    required this.manifest,
    required this.runtime,
    required this.manualOptions,
    required this.commentOptions,
    required this.randomSeed,
    required this.systemPrompt,
    required this.piperManifest,
    required this.piperRuntime,
  });

  /// Parses and validates the compile-time local assistant configuration.
  factory AssistantBuildConfiguration.fromEnvironment({
    String modelId = CompilationConstants.qwenModelId,
    String modelUrl = CompilationConstants.qwenModelUrl,
    String modelRevision = CompilationConstants.qwenModelRevision,
    String modelFilename = CompilationConstants.qwenModelFilename,
    String modelSizeBytes = CompilationConstants.qwenModelSizeBytes,
    String modelSha256 = CompilationConstants.qwenModelSha256,
    String modelLicense = CompilationConstants.qwenModelLicense,
    String downloadReserveBytes = CompilationConstants.qwenDownloadReserveBytes,
    String contextTokens = CompilationConstants.qwenContextTokens,
    String batchTokens = CompilationConstants.qwenBatchTokens,
    String threadCount = CompilationConstants.qwenThreadCount,
    String gpuLayers = CompilationConstants.qwenGpuLayers,
    String randomSeed = CompilationConstants.qwenRandomSeed,
    String systemPrompt = CompilationConstants.qwenSystemPrompt,
    String manualMaxTokens = CompilationConstants.qwenManualMaxTokens,
    String manualTemperature = CompilationConstants.qwenManualTemperature,
    String manualTopP = CompilationConstants.qwenManualTopP,
    String manualTopK = CompilationConstants.qwenManualTopK,
    String manualMinP = CompilationConstants.qwenManualMinP,
    String commentMaxTokens = CompilationConstants.qwenCommentMaxTokens,
    String commentTemperature = CompilationConstants.qwenCommentTemperature,
    String commentTopP = CompilationConstants.qwenCommentTopP,
    String commentTopK = CompilationConstants.qwenCommentTopK,
    String commentMinP = CompilationConstants.qwenCommentMinP,
    String piperModelId = CompilationConstants.piperModelId,
    String piperModelUrl = CompilationConstants.piperModelUrl,
    String piperModelRevision = CompilationConstants.piperModelRevision,
    String piperModelArchiveFilename = CompilationConstants.piperModelArchiveFilename,
    String piperModelArchiveSizeBytes = CompilationConstants.piperModelArchiveSizeBytes,
    String piperModelArchiveSha256 = CompilationConstants.piperModelArchiveSha256,
    String piperModelExpandedArchiveSizeBytes = CompilationConstants.piperModelExpandedArchiveSizeBytes,
    String piperModelExtractedSizeBytes = CompilationConstants.piperModelExtractedSizeBytes,
    String piperModelExtractedFileCount = CompilationConstants.piperModelExtractedFileCount,
    String piperModelBundleTreeSha256 = CompilationConstants.piperModelBundleTreeSha256,
    String piperModelArchiveRoot = CompilationConstants.piperModelArchiveRoot,
    String piperModelFilename = CompilationConstants.piperModelFilename,
    String piperTokensFilename = CompilationConstants.piperTokensFilename,
    String piperEspeakDataDirectory = CompilationConstants.piperEspeakDataDirectory,
    String piperModelLicense = CompilationConstants.piperModelLicense,
    String piperDownloadReserveBytes = CompilationConstants.piperDownloadReserveBytes,
    String piperProvider = CompilationConstants.piperProvider,
    String piperThreadCount = CompilationConstants.piperThreadCount,
    String piperSpeakerId = CompilationConstants.piperSpeakerId,
    String piperNoiseScale = CompilationConstants.piperNoiseScale,
    String piperNoiseScaleW = CompilationConstants.piperNoiseScaleW,
    String piperLengthScale = CompilationConstants.piperLengthScale,
    String piperSpeed = CompilationConstants.piperSpeed,
    String piperSilenceScale = CompilationConstants.piperSilenceScale,
    String piperMaxSentences = CompilationConstants.piperMaxSentences,
    String piperDebug = CompilationConstants.piperDebug,
  }) {
    final parsedModelSizeBytes = _parseInteger(
      'QWEN_MODEL_SIZE_BYTES',
      modelSizeBytes,
      minimum: 1,
      maximum: _maxInt64,
    );
    final parsedDownloadReserveBytes = _parseInteger(
      'QWEN_DOWNLOAD_RESERVE_BYTES',
      downloadReserveBytes,
      minimum: 0,
      maximum: _maxInt64,
    );
    if (parsedModelSizeBytes + parsedDownloadReserveBytes > _maxInt64) {
      throw ArgumentError(
        'QWEN_MODEL_SIZE_BYTES plus QWEN_DOWNLOAD_RESERVE_BYTES must fit '
        'a signed 64-bit filesystem capacity.',
      );
    }
    final parsedContextTokens = _parseInteger(
      'QWEN_CONTEXT_TOKENS',
      contextTokens,
      minimum: 1,
      maximum: _maxInt32,
    );
    final parsedBatchTokens = _parseInteger(
      'QWEN_BATCH_TOKENS',
      batchTokens,
      minimum: 1,
      maximum: _maxInt32,
    );
    if (parsedBatchTokens > parsedContextTokens) {
      throw ArgumentError.value(
        batchTokens,
        'batchTokens',
        'QWEN_BATCH_TOKENS must be no larger than the context.',
      );
    }
    final parsedThreadCount = _parseInteger(
      'QWEN_THREAD_COUNT',
      threadCount,
      minimum: 1,
      maximum: _maxInt32,
    );
    final parsedGpuLayers = _parseInteger(
      'QWEN_GPU_LAYERS',
      gpuLayers,
      minimum: 0,
      maximum: _maxInt32,
    );
    final parsedRandomSeed = _parseInteger(
      'QWEN_RANDOM_SEED',
      randomSeed,
      minimum: 0,
      maximum: _maxUint32,
    );
    final normalizedSystemPrompt = systemPrompt.trim();
    if (normalizedSystemPrompt.isEmpty) {
      throw ArgumentError.value(
        systemPrompt,
        'systemPrompt',
        'QWEN_SYSTEM_PROMPT must not be empty.',
      );
    }
    final piper = _parsePiperConfiguration(
      modelId: piperModelId,
      modelUrl: piperModelUrl,
      modelRevision: piperModelRevision,
      archiveFilename: piperModelArchiveFilename,
      archiveSizeBytes: piperModelArchiveSizeBytes,
      archiveSha256: piperModelArchiveSha256,
      expandedArchiveSizeBytes: piperModelExpandedArchiveSizeBytes,
      extractedSizeBytes: piperModelExtractedSizeBytes,
      extractedFileCount: piperModelExtractedFileCount,
      bundleTreeSha256: piperModelBundleTreeSha256,
      archiveRoot: piperModelArchiveRoot,
      modelFilename: piperModelFilename,
      tokensFilename: piperTokensFilename,
      espeakDataDirectory: piperEspeakDataDirectory,
      modelLicense: piperModelLicense,
      downloadReserveBytes: piperDownloadReserveBytes,
      provider: piperProvider,
      threadCount: piperThreadCount,
      speakerId: piperSpeakerId,
      noiseScale: piperNoiseScale,
      noiseScaleW: piperNoiseScaleW,
      lengthScale: piperLengthScale,
      speed: piperSpeed,
      silenceScale: piperSilenceScale,
      maxSentences: piperMaxSentences,
      debug: piperDebug,
    );
    final qwenManifest = QwenModelManifest(
      modelId: modelId,
      downloadUrl: modelUrl,
      revision: modelRevision,
      filename: modelFilename,
      byteSize: parsedModelSizeBytes,
      sha256: modelSha256,
      license: modelLicense,
      downloadReserveBytes: parsedDownloadReserveBytes,
    );
    _validateSharedCachePaths(qwenManifest, piper.manifest);

    return AssistantBuildConfiguration._(
      manifest: qwenManifest,
      runtime: LlamaRuntimeConfiguration(
        contextTokens: parsedContextTokens,
        batchTokens: parsedBatchTokens,
        threadCount: parsedThreadCount,
        gpuLayers: parsedGpuLayers,
      ),
      manualOptions: _parseGenerationOptions(
        prefix: 'QWEN_MANUAL',
        contextTokens: parsedContextTokens,
        maxTokens: manualMaxTokens,
        temperature: manualTemperature,
        topP: manualTopP,
        topK: manualTopK,
        minP: manualMinP,
      ),
      commentOptions: _parseGenerationOptions(
        prefix: 'QWEN_COMMENT',
        contextTokens: parsedContextTokens,
        maxTokens: commentMaxTokens,
        temperature: commentTemperature,
        topP: commentTopP,
        topK: commentTopK,
        minP: commentMinP,
      ),
      randomSeed: parsedRandomSeed,
      systemPrompt: normalizedSystemPrompt,
      piperManifest: piper.manifest,
      piperRuntime: piper.runtime,
    );
  }

  /// Pinned runtime acquisition manifest.
  final QwenModelManifest manifest;

  /// llama.cpp context and execution policy.
  final LlamaRuntimeConfiguration runtime;

  /// Sampling policy for manual `/think` dialogue.
  final GenerationOptions manualOptions;

  /// Sampling policy for short `/no_think` comments.
  final GenerationOptions commentOptions;

  /// Unsigned sampler base seed interpreted by the generation adapter.
  final int randomSeed;

  /// Shared Qwen system instruction.
  final String systemPrompt;

  /// Pinned Piper archive and extracted-bundle integrity manifest.
  final PiperModelManifest piperManifest;

  /// sherpa-onnx execution and decoding policy.
  final PiperRuntimeConfiguration piperRuntime;
}

void _validateSharedCachePaths(
  QwenModelManifest qwen,
  PiperModelManifest piper,
) {
  final entries = <(String, String)>[
    ('QWEN_MODEL_FILENAME', qwen.filename),
    ('Qwen partial download', '${qwen.filename}.part'),
    ('PIPER_MODEL_ARCHIVE_FILENAME', piper.archiveFilename),
    ('Piper partial download', '${piper.archiveFilename}.part'),
    ('PIPER_MODEL_ARCHIVE_ROOT', piper.archiveRoot),
    ('Piper extraction directory', '${piper.archiveRoot}.extracting'),
    ('Piper expanded archive', '${piper.archiveRoot}.extracting.tar'),
  ];
  final ownersByPath = <String, String>{};
  for (final (owner, path) in entries) {
    final normalizedPath = path.toLowerCase();
    final previousOwner = ownersByPath[normalizedPath];
    if (previousOwner != null) {
      throw ArgumentError(
        '$owner collides with $previousOwner in the shared model cache.',
      );
    }
    ownersByPath[normalizedPath] = owner;
  }
}

({PiperModelManifest manifest, PiperRuntimeConfiguration runtime}) _parsePiperConfiguration({
  required String modelId,
  required String modelUrl,
  required String modelRevision,
  required String archiveFilename,
  required String archiveSizeBytes,
  required String archiveSha256,
  required String expandedArchiveSizeBytes,
  required String extractedSizeBytes,
  required String extractedFileCount,
  required String bundleTreeSha256,
  required String archiveRoot,
  required String modelFilename,
  required String tokensFilename,
  required String espeakDataDirectory,
  required String modelLicense,
  required String downloadReserveBytes,
  required String provider,
  required String threadCount,
  required String speakerId,
  required String noiseScale,
  required String noiseScaleW,
  required String lengthScale,
  required String speed,
  required String silenceScale,
  required String maxSentences,
  required String debug,
}) {
  final parsedArchiveSizeBytes = _parseInteger(
    'PIPER_MODEL_ARCHIVE_SIZE_BYTES',
    archiveSizeBytes,
    minimum: 1,
    maximum: _maxInt64,
  );
  final parsedExtractedSizeBytes = _parseInteger(
    'PIPER_MODEL_EXTRACTED_SIZE_BYTES',
    extractedSizeBytes,
    minimum: 1,
    maximum: _maxInt64,
  );
  final parsedExpandedArchiveSizeBytes = _parseInteger(
    'PIPER_MODEL_EXPANDED_ARCHIVE_SIZE_BYTES',
    expandedArchiveSizeBytes,
    minimum: 1,
    maximum: _maxInt64,
  );
  final parsedExtractedFileCount = _parseInteger(
    'PIPER_MODEL_EXTRACTED_FILE_COUNT',
    extractedFileCount,
    minimum: 1,
    maximum: _maxInt32,
  );
  final parsedDownloadReserveBytes = _parseInteger(
    'PIPER_DOWNLOAD_RESERVE_BYTES',
    downloadReserveBytes,
    minimum: 0,
    maximum: _maxInt64,
  );
  if (parsedArchiveSizeBytes > _maxInt64 - parsedExpandedArchiveSizeBytes ||
      parsedArchiveSizeBytes + parsedExpandedArchiveSizeBytes > _maxInt64 - parsedExtractedSizeBytes ||
      parsedArchiveSizeBytes + parsedExpandedArchiveSizeBytes + parsedExtractedSizeBytes >
          _maxInt64 - parsedDownloadReserveBytes) {
    throw ArgumentError(
      'PIPER_MODEL_ARCHIVE_SIZE_BYTES plus '
      'PIPER_MODEL_EXPANDED_ARCHIVE_SIZE_BYTES plus '
      'PIPER_MODEL_EXTRACTED_SIZE_BYTES plus PIPER_DOWNLOAD_RESERVE_BYTES '
      'must fit a signed 64-bit filesystem capacity.',
    );
  }

  final normalizedProvider = provider.trim();
  if (normalizedProvider != 'cpu') {
    throw ArgumentError.value(
      provider,
      'provider',
      'PIPER_PROVIDER must be "cpu" for the supported mobile runtime.',
    );
  }
  final parsedThreadCount = _parseInteger(
    'PIPER_THREAD_COUNT',
    threadCount,
    minimum: 1,
    maximum: _maxInt32,
  );
  final parsedSpeakerId = _parseInteger(
    'PIPER_SPEAKER_ID',
    speakerId,
    minimum: 0,
    maximum: 0,
  );
  final parsedNoiseScale = _parseNonNegativeFloat32(
    'PIPER_NOISE_SCALE',
    noiseScale,
  );
  final parsedNoiseScaleW = _parseNonNegativeFloat32(
    'PIPER_NOISE_SCALE_W',
    noiseScaleW,
  );
  final parsedLengthScale = _parsePositiveFloat32(
    'PIPER_LENGTH_SCALE',
    lengthScale,
  );
  final parsedSpeed = _parseFiniteDouble('PIPER_SPEED', speed);
  if (parsedSpeed <= 0 || parsedSpeed > _maxFloat32) {
    throw ArgumentError.value(
      speed,
      'speed',
      'PIPER_SPEED must be positive and fit a 32-bit float.',
    );
  }
  final parsedSilenceScale = _parseFiniteDouble(
    'PIPER_SILENCE_SCALE',
    silenceScale,
  );
  if (parsedSilenceScale < 0 || parsedSilenceScale > _maxFloat32) {
    throw ArgumentError.value(
      silenceScale,
      'silenceScale',
      'PIPER_SILENCE_SCALE must be non-negative and fit a 32-bit float.',
    );
  }
  final parsedMaxSentences = _parseInteger(
    'PIPER_MAX_SENTENCES',
    maxSentences,
    minimum: 1,
    maximum: _maxInt32,
  );
  final parsedDebug = _parseBoolean('PIPER_DEBUG', debug);

  return (
    manifest: PiperModelManifest(
      modelId: modelId,
      downloadUrl: modelUrl,
      revision: modelRevision,
      archiveFilename: archiveFilename,
      archiveByteSize: parsedArchiveSizeBytes,
      archiveSha256: archiveSha256,
      expandedArchiveByteSize: parsedExpandedArchiveSizeBytes,
      extractedByteSize: parsedExtractedSizeBytes,
      extractedFileCount: parsedExtractedFileCount,
      bundleTreeSha256: bundleTreeSha256,
      archiveRoot: archiveRoot,
      modelFilename: modelFilename,
      tokensFilename: tokensFilename,
      espeakDataDirectory: espeakDataDirectory,
      license: modelLicense,
      downloadReserveBytes: parsedDownloadReserveBytes,
    ),
    runtime: PiperRuntimeConfiguration(
      provider: normalizedProvider,
      threadCount: parsedThreadCount,
      speakerId: parsedSpeakerId,
      noiseScale: parsedNoiseScale,
      noiseScaleW: parsedNoiseScaleW,
      lengthScale: parsedLengthScale,
      speed: parsedSpeed,
      silenceScale: parsedSilenceScale,
      maxSentences: parsedMaxSentences,
      debug: parsedDebug,
    ),
  );
}

GenerationOptions _parseGenerationOptions({
  required String prefix,
  required int contextTokens,
  required String maxTokens,
  required String temperature,
  required String topP,
  required String topK,
  required String minP,
}) {
  final parsedMaxTokens = _parseInteger(
    '${prefix}_MAX_TOKENS',
    maxTokens,
    minimum: 1,
    maximum: _maxInt32,
  );
  final parsedTopK = _parseInteger(
    '${prefix}_TOP_K',
    topK,
    minimum: 1,
    maximum: _maxInt32,
  );
  final parsedTemperature = _parseFiniteDouble(
    '${prefix}_TEMPERATURE',
    temperature,
  );
  final parsedTopP = _parseFiniteDouble('${prefix}_TOP_P', topP);
  final parsedMinP = _parseFiniteDouble('${prefix}_MIN_P', minP);
  if (parsedMaxTokens >= contextTokens) {
    throw ArgumentError(
      '${prefix}_MAX_TOKENS must leave context space for a non-empty prompt.',
    );
  }
  if (parsedTemperature <= 0 ||
      parsedTemperature > _maxFloat32 ||
      parsedTopP <= 0 ||
      parsedTopP > 1 ||
      parsedMinP < 0 ||
      parsedMinP > 1) {
    throw ArgumentError(
      '$prefix sampling values are outside their supported ranges.',
    );
  }
  return GenerationOptions(
    maxTokens: parsedMaxTokens,
    temperature: parsedTemperature,
    topP: parsedTopP,
    topK: parsedTopK,
    minP: parsedMinP,
  );
}

int _parseInteger(
  String name,
  String value, {
  required int minimum,
  required int maximum,
}) {
  final parsed = int.tryParse(value);
  if (parsed == null) {
    throw FormatException('$name must be a base-10 integer.', value);
  }
  if (parsed < minimum || parsed > maximum) {
    throw ArgumentError.value(
      value,
      name,
      '$name must be between $minimum and $maximum.',
    );
  }
  return parsed;
}

double _parseFiniteDouble(String name, String value) {
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('$name must be a finite decimal value.', value);
  }
  return parsed;
}

double _parseNonNegativeFloat32(String name, String value) {
  final parsed = _parseFiniteDouble(name, value);
  if (parsed < 0 || parsed > _maxFloat32) {
    throw ArgumentError.value(
      value,
      name,
      '$name must be non-negative and fit a 32-bit float.',
    );
  }
  return parsed;
}

double _parsePositiveFloat32(String name, String value) {
  final parsed = _parseFiniteDouble(name, value);
  if (parsed <= 0 || parsed > _maxFloat32) {
    throw ArgumentError.value(
      value,
      name,
      '$name must be positive and fit a 32-bit float.',
    );
  }
  return parsed;
}

bool _parseBoolean(String name, String value) {
  return switch (value) {
    'true' => true,
    'false' => false,
    _ => throw FormatException('$name must be exactly "true" or "false".', value),
  };
}

const _maxInt32 = 0x7FFFFFFF;
const _maxUint32 = 0xFFFFFFFF;
const _maxInt64 = 0x7FFFFFFFFFFFFFFF;
const _maxFloat32 = 3.4028234663852886e38;
