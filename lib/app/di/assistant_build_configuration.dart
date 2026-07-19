import 'package:pov_agent/core/constants/compilation_constants.dart';
import 'package:pov_agent/features/assistant/application/models/generation_options.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_native_runtime.dart';
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
  });

  /// Parses and validates the compile-time Qwen configuration.
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

    return AssistantBuildConfiguration._(
      manifest: QwenModelManifest(
        modelId: modelId,
        downloadUrl: modelUrl,
        revision: modelRevision,
        filename: modelFilename,
        byteSize: parsedModelSizeBytes,
        sha256: modelSha256,
        license: modelLicense,
        downloadReserveBytes: parsedDownloadReserveBytes,
      ),
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

  /// Unsigned llama.cpp distribution-sampler seed.
  final int randomSeed;

  /// Shared Qwen system instruction.
  final String systemPrompt;
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

const _maxInt32 = 0x7FFFFFFF;
const _maxUint32 = 0xFFFFFFFF;
const _maxInt64 = 0x7FFFFFFFFFFFFFFF;
const _maxFloat32 = 3.4028234663852886e38;
