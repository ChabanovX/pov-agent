import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pov_agent/features/assistant/data/ffi/llama_bridge_bindings.dart';

const _nativeComplete = 1;
const _errorBufferLength = 2048;
const _tokenBufferLength = 8192;

/// Native runtime parameters passed from compile-time application composition.
final class LlamaRuntimeConfiguration {
  /// Creates a validated runtime configuration.
  const LlamaRuntimeConfiguration({
    required this.contextTokens,
    required this.batchTokens,
    required this.threadCount,
    required this.gpuLayers,
  });

  /// Maximum model context in tokens.
  final int contextTokens;

  /// Maximum prompt batch decoded by one native call.
  final int batchTokens;

  /// CPU thread count used by llama.cpp.
  final int threadCount;

  /// Accelerator layers requested before native CPU fallback.
  final int gpuLayers;
}

/// Sampling values consumed by one native generation.
final class LlamaSamplingConfiguration {
  /// Creates one sampling configuration.
  const LlamaSamplingConfiguration({
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.minP,
    required this.seed,
  });

  /// Maximum number of generated tokens.
  final int maxTokens;

  /// Temperature applied before distribution sampling.
  final double temperature;

  /// Nucleus sampling threshold.
  final double topP;

  /// Top-k candidate count.
  final int topK;

  /// Minimum probability threshold.
  final double minP;

  /// Unsigned llama.cpp sampler seed.
  final int seed;
}

/// Failure returned by the project-owned native bridge.
final class LlamaNativeException implements Exception {
  /// Creates a failure with a native [status] and diagnostic [message].
  const LlamaNativeException(this.status, this.message);

  /// Stable bridge status code.
  final int status;

  /// Native diagnostic safe for logging, not direct presentation.
  final String message;

  @override
  String toString() => 'LlamaNativeException($status, $message)';
}

/// One token-step result produced by [LlamaNativeRuntime].
sealed class LlamaTokenStep {
  const LlamaTokenStep();
}

/// A byte fragment from one decoded token.
final class LlamaTokenBytes extends LlamaTokenStep {
  /// Creates a token fragment with an owned copy of [bytes].
  LlamaTokenBytes(Uint8List bytes) : bytes = Uint8List.fromList(bytes);

  /// Raw UTF-8 bytes; a Unicode scalar may span adjacent fragments.
  final Uint8List bytes;
}

/// The model reached EOG or the configured token limit.
final class LlamaGenerationComplete extends LlamaTokenStep {
  /// Creates the terminal token-step marker.
  const LlamaGenerationComplete();
}

/// Isolate-owned wrapper around one opaque llama.cpp runtime.
///
/// Every method is synchronous by design. Callers must keep this object on the
/// inference isolate so model loading and decoding never block Flutter's UI.
final class LlamaNativeRuntime {
  LlamaNativeRuntime._(
    this._runtime,
    this.usesGpu,
    this._tokenBuffer,
    this._tokenLength,
    this._errorBuffer,
  );

  /// Loads [modelPath] through the project-owned bridge.
  factory LlamaNativeRuntime.load(
    String modelPath,
    LlamaRuntimeConfiguration configuration,
  ) {
    final nativePath = modelPath.toNativeUtf8();
    final errorBuffer = calloc<Uint8>(_errorBufferLength);
    final tokenBuffer = calloc<Uint8>(_tokenBufferLength);
    final tokenLength = calloc<Int32>();
    var runtime = nullptr.cast<PovLlamaRuntime>();
    try {
      runtime = LlamaBridgeBindings.create(
        nativePath,
        configuration.contextTokens,
        configuration.batchTokens,
        configuration.threadCount,
        configuration.gpuLayers,
        errorBuffer,
        _errorBufferLength,
      );
      if (runtime == nullptr) {
        final message = _decodeNullTerminated(errorBuffer, _errorBufferLength);
        throw LlamaNativeException(
          -2,
          message.isEmpty ? 'The native runtime could not load the model.' : message,
        );
      }
      return LlamaNativeRuntime._(
        runtime,
        LlamaBridgeBindings.usesGpu(runtime),
        tokenBuffer,
        tokenLength,
        errorBuffer,
      );
    } on Object {
      if (runtime != nullptr) LlamaBridgeBindings.destroy(runtime);
      calloc
        ..free(tokenBuffer)
        ..free(tokenLength)
        ..free(errorBuffer);
      rethrow;
    } finally {
      calloc.free(nativePath);
    }
  }

  Pointer<PovLlamaRuntime> _runtime;
  final Pointer<Uint8> _tokenBuffer;
  final Pointer<Int32> _tokenLength;
  final Pointer<Uint8> _errorBuffer;

  /// Whether the loaded model is currently offloaded to an accelerator.
  final bool usesGpu;

  /// Starts a fresh generation after clearing previous native state.
  void begin(String prompt, LlamaSamplingConfiguration sampling) {
    _ensureOpen();
    final nativePrompt = prompt.toNativeUtf8();
    try {
      final status = LlamaBridgeBindings.beginGeneration(
        _runtime,
        nativePrompt,
        sampling.maxTokens,
        sampling.temperature,
        sampling.topP,
        sampling.topK,
        sampling.minP,
        sampling.seed,
      );
      if (status < 0) throw _exceptionFor(status);
    } finally {
      calloc.free(nativePrompt);
    }
  }

  /// Advances generation by one cooperatively cancellable decode step.
  LlamaTokenStep next() {
    _ensureOpen();
    final status = LlamaBridgeBindings.nextToken(
      _runtime,
      _tokenBuffer,
      _tokenBufferLength,
      _tokenLength,
    );
    if (status == _nativeComplete) return const LlamaGenerationComplete();
    if (status < 0) throw _exceptionFor(status);

    final length = _tokenLength.value;
    return LlamaTokenBytes(
      Uint8List.fromList(_tokenBuffer.asTypedList(length)),
    );
  }

  /// Cancels active sampling and clears its KV memory.
  void cancel() {
    if (_runtime == nullptr) return;
    final status = LlamaBridgeBindings.cancelGeneration(_runtime);
    if (status < 0) throw _exceptionFor(status);
  }

  /// Releases all native resources exactly once.
  ///
  /// A failed native quiescence leaves the runtime open so callers can report
  /// the diagnostic and retry cleanup instead of acknowledging a false unload.
  void close() {
    if (_runtime == nullptr) return;
    final status = LlamaBridgeBindings.destroy(_runtime);
    if (status < 0) throw _exceptionFor(status);
    _runtime = nullptr;
    calloc
      ..free(_tokenBuffer)
      ..free(_tokenLength)
      ..free(_errorBuffer);
  }

  LlamaNativeException _exceptionFor(int status) {
    _errorBuffer
        .asTypedList(_errorBufferLength)
        .fillRange(
          0,
          _errorBufferLength,
          0,
        );
    LlamaBridgeBindings.copyError(
      _runtime,
      _errorBuffer,
      _errorBufferLength,
    );
    final message = _decodeNullTerminated(_errorBuffer, _errorBufferLength);
    return LlamaNativeException(
      status,
      message.isEmpty ? 'The native llama.cpp operation failed.' : message,
    );
  }

  void _ensureOpen() {
    if (_runtime == nullptr) {
      throw StateError('The native llama.cpp runtime is closed.');
    }
  }
}

String _decodeNullTerminated(Pointer<Uint8> pointer, int capacity) {
  final bytes = pointer.asTypedList(capacity);
  final end = bytes.indexOf(0);
  return utf8.decode(
    bytes.sublist(0, end < 0 ? capacity : end),
    allowMalformed: true,
  );
}
