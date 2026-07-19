import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _assetId =
    'package:pov_agent/features/assistant/data/ffi/'
    'llama_bridge_bindings.dart';

/// Opaque owner of one native llama.cpp model and context.
final class PovLlamaRuntime extends Opaque {}

@Native<
  Pointer<PovLlamaRuntime> Function(
    Pointer<Utf8>,
    Int32,
    Int32,
    Int32,
    Int32,
    Pointer<Uint8>,
    Int32,
  )
>(symbol: 'pov_llama_create', assetId: _assetId)
external Pointer<PovLlamaRuntime> _create(
  Pointer<Utf8> modelPath,
  int contextTokens,
  int batchTokens,
  int threadCount,
  int gpuLayers,
  Pointer<Uint8> errorBuffer,
  int errorBufferLength,
);

@Native<Int32 Function(Pointer<PovLlamaRuntime>)>(
  symbol: 'pov_llama_destroy',
  assetId: _assetId,
)
external int _destroy(Pointer<PovLlamaRuntime> runtime);

@Native<
  Int32 Function(
    Pointer<PovLlamaRuntime>,
    Pointer<Utf8>,
    Int32,
    Float,
    Float,
    Int32,
    Float,
    Uint32,
  )
>(symbol: 'pov_llama_begin_generation', assetId: _assetId)
external int _beginGeneration(
  Pointer<PovLlamaRuntime> runtime,
  Pointer<Utf8> prompt,
  int maxTokens,
  double temperature,
  double topP,
  int topK,
  double minP,
  int seed,
);

@Native<
  Int32 Function(
    Pointer<PovLlamaRuntime>,
    Pointer<Uint8>,
    Int32,
    Pointer<Int32>,
  )
>(symbol: 'pov_llama_next_token', assetId: _assetId)
external int _nextToken(
  Pointer<PovLlamaRuntime> runtime,
  Pointer<Uint8> outputBuffer,
  int outputBufferLength,
  Pointer<Int32> outputLength,
);

@Native<Int32 Function(Pointer<PovLlamaRuntime>)>(
  symbol: 'pov_llama_cancel_generation',
  assetId: _assetId,
)
external int _cancelGeneration(Pointer<PovLlamaRuntime> runtime);

@Native<Int32 Function(Pointer<PovLlamaRuntime>, Pointer<Uint8>, Int32)>(
  symbol: 'pov_llama_copy_error',
  assetId: _assetId,
)
external int _copyError(
  Pointer<PovLlamaRuntime> runtime,
  Pointer<Uint8> errorBuffer,
  int errorBufferLength,
);

@Native<Int32 Function(Pointer<PovLlamaRuntime>)>(
  symbol: 'pov_llama_uses_gpu',
  assetId: _assetId,
)
external int _usesGpu(Pointer<PovLlamaRuntime> runtime);

/// Direct bindings used only by the inference worker isolate.
abstract final class LlamaBridgeBindings {
  /// Loads a model and context, returning a null pointer on failure.
  static Pointer<PovLlamaRuntime> create(
    Pointer<Utf8> modelPath,
    int contextTokens,
    int batchTokens,
    int threadCount,
    int gpuLayers,
    Pointer<Uint8> errorBuffer,
    int errorBufferLength,
  ) {
    return _create(
      modelPath,
      contextTokens,
      batchTokens,
      threadCount,
      gpuLayers,
      errorBuffer,
      errorBufferLength,
    );
  }

  /// Frees the native model, context, sampler, and backend resources.
  static int destroy(Pointer<PovLlamaRuntime> runtime) => _destroy(runtime);

  /// Tokenizes and decodes a prompt, then initializes its sampler.
  static int beginGeneration(
    Pointer<PovLlamaRuntime> runtime,
    Pointer<Utf8> prompt,
    int maxTokens,
    double temperature,
    double topP,
    int topK,
    double minP,
    int seed,
  ) {
    return _beginGeneration(
      runtime,
      prompt,
      maxTokens,
      temperature,
      topP,
      topK,
      minP,
      seed,
    );
  }

  /// Decodes at most one token piece into [outputBuffer].
  static int nextToken(
    Pointer<PovLlamaRuntime> runtime,
    Pointer<Uint8> outputBuffer,
    int outputBufferLength,
    Pointer<Int32> outputLength,
  ) {
    return _nextToken(
      runtime,
      outputBuffer,
      outputBufferLength,
      outputLength,
    );
  }

  /// Ends the active generation and clears its native sampling state.
  static int cancelGeneration(Pointer<PovLlamaRuntime> runtime) {
    return _cancelGeneration(runtime);
  }

  /// Copies the latest native diagnostic into [errorBuffer].
  static int copyError(
    Pointer<PovLlamaRuntime> runtime,
    Pointer<Uint8> errorBuffer,
    int errorBufferLength,
  ) {
    return _copyError(runtime, errorBuffer, errorBufferLength);
  }

  /// Whether the loaded model uses a GPU backend.
  static bool usesGpu(Pointer<PovLlamaRuntime> runtime) {
    return _usesGpu(runtime) == 1;
  }
}
