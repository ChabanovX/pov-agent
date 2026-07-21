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

  /// Number of model layers requested from an available accelerator.
  static const String qwenGpuLayers = String.fromEnvironment(
    'QWEN_GPU_LAYERS',
    defaultValue: '99',
  );

  /// Sampler base seed; fixed values sequence short comments deterministically.
  ///
  /// Manual requests use the value directly. `2^32 - 1` asks llama.cpp to
  /// choose a random seed for every request instead of deriving a sequence.
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
    defaultValue: '40',
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

  /// Stable upstream identifier for the selected Piper voice bundle.
  static const String piperModelId = String.fromEnvironment(
    'PIPER_MODEL_ID',
    defaultValue: 'k2-fsa/sherpa-onnx/vits-piper-en_US-ljspeech-medium-int8',
  );

  /// Download URL for the checksum-pinned Piper voice archive.
  static const String piperModelUrl = String.fromEnvironment(
    'PIPER_MODEL_URL',
    defaultValue:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
  );

  /// Upstream release tag containing the selected voice archive.
  static const String piperModelRevision = String.fromEnvironment(
    'PIPER_MODEL_REVISION',
    defaultValue: 'tts-models',
  );

  /// Cached filename of the selected voice archive.
  static const String piperModelArchiveFilename = String.fromEnvironment(
    'PIPER_MODEL_ARCHIVE_FILENAME',
    defaultValue: 'vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
  );

  /// Exact compressed byte length required before extraction.
  static const String piperModelArchiveSizeBytes = String.fromEnvironment(
    'PIPER_MODEL_ARCHIVE_SIZE_BYTES',
    defaultValue: '21090429',
  );

  /// SHA-256 required before the voice archive can be extracted.
  static const String piperModelArchiveSha256 = String.fromEnvironment(
    'PIPER_MODEL_ARCHIVE_SHA256',
    defaultValue: '24dc3bd77dd48c291e52c297878d3437c9492f245d823d7f6a06c4bbb67f4b6b',
  );

  /// Exact tar length temporarily materialized during bzip2 extraction.
  static const String piperModelExpandedArchiveSizeBytes = String.fromEnvironment(
    'PIPER_MODEL_EXPANDED_ARCHIVE_SIZE_BYTES',
    defaultValue: '37662720',
  );

  /// Exact byte length of all regular files in the extracted bundle.
  static const String piperModelExtractedSizeBytes = String.fromEnvironment(
    'PIPER_MODEL_EXTRACTED_SIZE_BYTES',
    defaultValue: '37347875',
  );

  /// Exact number of regular files in the extracted bundle.
  static const String piperModelExtractedFileCount = String.fromEnvironment(
    'PIPER_MODEL_EXTRACTED_FILE_COUNT',
    defaultValue: '359',
  );

  /// Canonical tree SHA-256 required before the bundle can be published.
  static const String piperModelBundleTreeSha256 = String.fromEnvironment(
    'PIPER_MODEL_BUNDLE_TREE_SHA256',
    defaultValue: 'a38256a8fada764a1e7b450c5f307b7b5de159e137af1a6aae0b2326f355bc3b',
  );

  /// Single archive root that contains the selected Piper bundle.
  static const String piperModelArchiveRoot = String.fromEnvironment(
    'PIPER_MODEL_ARCHIVE_ROOT',
    defaultValue: 'vits-piper-en_US-ljspeech-medium-int8',
  );

  /// ONNX graph filename inside the extracted bundle root.
  static const String piperModelFilename = String.fromEnvironment(
    'PIPER_MODEL_FILENAME',
    defaultValue: 'en_US-ljspeech-medium.onnx',
  );

  /// Token-table filename inside the extracted bundle root.
  static const String piperTokensFilename = String.fromEnvironment(
    'PIPER_TOKENS_FILENAME',
    defaultValue: 'tokens.txt',
  );

  /// eSpeak data directory inside the extracted bundle root.
  static const String piperEspeakDataDirectory = String.fromEnvironment(
    'PIPER_ESPEAK_DATA_DIRECTORY',
    defaultValue: 'espeak-ng-data',
  );

  /// License identifier recorded by the pinned voice repository.
  static const String piperModelLicense = String.fromEnvironment(
    'PIPER_MODEL_LICENSE',
    defaultValue: 'Public-Domain',
  );

  /// Free-space reserve retained beyond archive and extracted bundle bytes.
  static const String piperDownloadReserveBytes = String.fromEnvironment(
    'PIPER_DOWNLOAD_RESERVE_BYTES',
    defaultValue: '33554432',
  );

  /// sherpa-onnx execution provider used by the local Piper runtime.
  static const String piperProvider = String.fromEnvironment(
    'PIPER_PROVIDER',
    defaultValue: 'cpu',
  );

  /// CPU thread count used while synthesizing one utterance.
  static const String piperThreadCount = String.fromEnvironment(
    'PIPER_THREAD_COUNT',
    defaultValue: '1',
  );

  /// Voice speaker selected from the single-speaker LJSpeech model.
  static const String piperSpeakerId = String.fromEnvironment(
    'PIPER_SPEAKER_ID',
    defaultValue: '0',
  );

  /// VITS waveform-noise scale used while loading the voice model.
  static const String piperNoiseScale = String.fromEnvironment(
    'PIPER_NOISE_SCALE',
    defaultValue: '0.667',
  );

  /// VITS duration-noise scale used while loading the voice model.
  static const String piperNoiseScaleW = String.fromEnvironment(
    'PIPER_NOISE_SCALE_W',
    defaultValue: '0.8',
  );

  /// VITS duration multiplier used while loading the voice model.
  static const String piperLengthScale = String.fromEnvironment(
    'PIPER_LENGTH_SCALE',
    defaultValue: '1.0',
  );

  /// Piper speech-rate multiplier.
  static const String piperSpeed = String.fromEnvironment(
    'PIPER_SPEED',
    defaultValue: '1.0',
  );

  /// Silence scale applied by the Piper generator.
  static const String piperSilenceScale = String.fromEnvironment(
    'PIPER_SILENCE_SCALE',
    defaultValue: '0.2',
  );

  /// Maximum number of sentence chunks synthesized per native request.
  static const String piperMaxSentences = String.fromEnvironment(
    'PIPER_MAX_SENTENCES',
    defaultValue: '1',
  );

  /// Whether sherpa-onnx emits native diagnostic logging.
  static const String piperDebug = String.fromEnvironment(
    'PIPER_DEBUG',
    defaultValue: 'false',
  );

  /// Preferred English locale requested from the system speech runtime.
  static const String systemSpeechLanguage = String.fromEnvironment(
    'SYSTEM_SPEECH_LANGUAGE',
    defaultValue: 'en-US',
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
