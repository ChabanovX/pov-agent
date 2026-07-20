/// Compile-time flags that select application composition.
abstract final class CompilationConstants {
  /// Uses the bundled video stream instead of the device camera.
  static bool get usesRecordedVideo => _parseCompileTimeBoolean(
    'USE_RECORDED_VIDEO',
    _usesRecordedVideoValue,
  );

  static const String _usesRecordedVideoValue = String.fromEnvironment(
    'USE_RECORDED_VIDEO',
    defaultValue: 'false',
  );

  /// Stable upstream repository identifier for the selected model.
  static const String qwenModelId = String.fromEnvironment(
    'QWEN_MODEL_ID',
    defaultValue: 'unsloth/Qwen3-0.6B-GGUF',
  );

  /// Immutable download URL for the selected Qwen GGUF revision.
  static const String qwenModelUrl = String.fromEnvironment(
    'QWEN_MODEL_URL',
    defaultValue:
        'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/'
        '272676c9e0eb9f33a7719ba3d27482fbb445e801/'
        'Qwen3-0.6B-Q4_K_M.gguf?download=true',
  );

  /// Immutable Hugging Face revision containing the selected GGUF.
  static const String qwenModelRevision = String.fromEnvironment(
    'QWEN_MODEL_REVISION',
    defaultValue: '272676c9e0eb9f33a7719ba3d27482fbb445e801',
  );

  /// Cached filename of the selected GGUF.
  static const String qwenModelFilename = String.fromEnvironment(
    'QWEN_MODEL_FILENAME',
    defaultValue: 'Qwen3-0.6B-Q4_K_M.gguf',
  );

  /// Exact byte length required before the model can be verified.
  static const String qwenModelSizeBytes = String.fromEnvironment(
    'QWEN_MODEL_SIZE_BYTES',
    defaultValue: '396705472',
  );

  /// SHA-256 required before the cached model can be loaded.
  static const String qwenModelSha256 = String.fromEnvironment(
    'QWEN_MODEL_SHA256',
    defaultValue: 'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a',
  );

  /// License identifier recorded by the pinned model repository.
  static const String qwenModelLicense = String.fromEnvironment(
    'QWEN_MODEL_LICENSE',
    defaultValue: 'Apache-2.0',
  );

  /// Free-space reserve retained in addition to the model download size.
  static const String qwenDownloadReserveBytes = String.fromEnvironment(
    'QWEN_DOWNLOAD_RESERVE_BYTES',
    defaultValue: '67108864',
  );

  /// Maximum llama context used by the MVP runtime.
  static const String qwenContextTokens = String.fromEnvironment(
    'QWEN_CONTEXT_TOKENS',
    defaultValue: '2048',
  );

  /// Maximum prompt batch decoded by one native call.
  static const String qwenBatchTokens = String.fromEnvironment(
    'QWEN_BATCH_TOKENS',
    defaultValue: '512',
  );

  /// CPU thread count used for prompt and token decoding.
  static const String qwenThreadCount = String.fromEnvironment(
    'QWEN_THREAD_COUNT',
    defaultValue: '4',
  );

  /// Number of model layers requested from Metal before CPU fallback.
  static const String qwenGpuLayers = String.fromEnvironment(
    'QWEN_GPU_LAYERS',
    defaultValue: '99',
  );

  /// Sampler seed; `2^32 - 1` asks llama.cpp to choose a random seed.
  static const String qwenRandomSeed = String.fromEnvironment(
    'QWEN_RANDOM_SEED',
    defaultValue: '4294967295',
  );

  /// System instruction shared by manual and observer prompts.
  static const String qwenSystemPrompt = String.fromEnvironment(
    'QWEN_SYSTEM_PROMPT',
    defaultValue:
        'You are POV Agent, a helpful local assistant. '
        'Always answer in English.',
  );

  /// Maximum generated tokens for a manual `/think` request.
  static const String qwenManualMaxTokens = String.fromEnvironment(
    'QWEN_MANUAL_MAX_TOKENS',
    defaultValue: '512',
  );

  /// Temperature for a manual `/think` request.
  static const String qwenManualTemperature = String.fromEnvironment(
    'QWEN_MANUAL_TEMPERATURE',
    defaultValue: '0.6',
  );

  /// Top-p threshold for a manual `/think` request.
  static const String qwenManualTopP = String.fromEnvironment(
    'QWEN_MANUAL_TOP_P',
    defaultValue: '0.95',
  );

  /// Top-k threshold for a manual `/think` request.
  static const String qwenManualTopK = String.fromEnvironment(
    'QWEN_MANUAL_TOP_K',
    defaultValue: '20',
  );

  /// Min-p threshold for a manual `/think` request.
  static const String qwenManualMinP = String.fromEnvironment(
    'QWEN_MANUAL_MIN_P',
    defaultValue: '0.0',
  );

  /// Maximum generated tokens for a short `/no_think` comment.
  static const String qwenCommentMaxTokens = String.fromEnvironment(
    'QWEN_COMMENT_MAX_TOKENS',
    defaultValue: '16',
  );

  /// Temperature for a short `/no_think` comment.
  static const String qwenCommentTemperature = String.fromEnvironment(
    'QWEN_COMMENT_TEMPERATURE',
    defaultValue: '0.7',
  );

  /// Top-p threshold for a short `/no_think` comment.
  static const String qwenCommentTopP = String.fromEnvironment(
    'QWEN_COMMENT_TOP_P',
    defaultValue: '0.8',
  );

  /// Top-k threshold for a short `/no_think` comment.
  static const String qwenCommentTopK = String.fromEnvironment(
    'QWEN_COMMENT_TOP_K',
    defaultValue: '20',
  );

  /// Min-p threshold for a short `/no_think` comment.
  static const String qwenCommentMinP = String.fromEnvironment(
    'QWEN_COMMENT_MIN_P',
    defaultValue: '0.0',
  );
}

bool _parseCompileTimeBoolean(String name, String value) {
  return switch (value) {
    'true' => true,
    'false' => false,
    _ => throw FormatException(
      '$name must be exactly "true" or "false".',
      value,
    ),
  };
}
