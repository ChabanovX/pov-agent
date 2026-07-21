import 'dart:async';

import 'package:meta/meta.dart';
import 'package:pov_agent/features/assistant/application/models/piper_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/generated_speech_audio_player.dart';
import 'package:pov_agent/features/assistant/data/ffi/piper_speech_generator.dart';
import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Speaks with a verified Piper voice and a short-lived sherpa-onnx runtime.
///
/// Each call is single-flight. Model preparation may download on the first
/// attempt, synthesis runs off the UI isolate, and the generator contract frees
/// Piper before [GeneratedSpeechAudioPlayer.play] begins. Stop invalidates the
/// operation immediately but awaits non-preemptible single-sentence generation
/// so completion still guarantees that native model memory is quiescent.
final class PiperSpeechSynthesizer implements SpeechSynthesizer {
  /// Creates the local speech adapter from explicit acquisition and I/O seams.
  PiperSpeechSynthesizer({
    required ModelStore<VerifiedPiperModelBundle> modelStore,
    required PiperSpeechGenerator generator,
    required GeneratedSpeechAudioPlayer audioPlayer,
    required PiperRuntimeConfiguration configuration,
  }) : this._(modelStore, generator, audioPlayer, configuration);

  PiperSpeechSynthesizer._(
    this._modelStore,
    this._generator,
    this._audioPlayer,
    this._configuration,
  );

  final ModelStore<VerifiedPiperModelBundle> _modelStore;
  final PiperSpeechGenerator _generator;
  final GeneratedSpeechAudioPlayer _audioPlayer;
  final PiperRuntimeConfiguration _configuration;

  _PiperSpeechOperation? _active;
  Future<AppResult<void>>? _stopTask;
  Future<AppResult<void>>? _closeTask;
  var _closed = false;
  var _nativeRuntimeActive = false;
  var _synthesisAttempts = 0;
  var _synthesisSettlements = 0;
  var _completedPlaybacks = 0;
  var _lastSampleCount = 0;
  var _lastSampleRateHz = 0;
  var _lastPeakAmplitude = 0.0;
  DateTime? _lastNativeRuntimeCreatedAtUtc;
  DateTime? _lastNativeRuntimeFreedAtUtc;

  /// Whether `OfflineTts` construction succeeded and its free has not returned.
  @visibleForTesting
  bool get nativeRuntimeActive => _nativeRuntimeActive;

  /// Worker timestamp immediately after the latest `OfflineTts` construction.
  @visibleForTesting
  DateTime? get lastNativeRuntimeCreatedAtUtc => _lastNativeRuntimeCreatedAtUtc;

  /// Worker timestamp immediately after the latest `OfflineTts.free()` return.
  @visibleForTesting
  DateTime? get lastNativeRuntimeFreedAtUtc => _lastNativeRuntimeFreedAtUtc;

  /// Number of synthesis tasks submitted to the sherpa boundary.
  @visibleForTesting
  int get synthesisAttempts => _synthesisAttempts;

  /// Number of submitted synthesis tasks that reached terminal settlement.
  @visibleForTesting
  int get synthesisSettlements => _synthesisSettlements;

  /// Number of local utterances that reached terminal playback completion.
  @visibleForTesting
  int get completedPlaybacks => _completedPlaybacks;

  /// Sample count produced by the most recent successful synthesis.
  @visibleForTesting
  int get lastSampleCount => _lastSampleCount;

  /// Sample rate produced by the most recent successful synthesis.
  @visibleForTesting
  int get lastSampleRateHz => _lastSampleRateHz;

  /// Peak absolute amplitude produced by the most recent synthesis.
  @visibleForTesting
  double get lastPeakAmplitude => _lastPeakAmplitude;

  /// Typed Piper store exposed only to native acceptance probes.
  @visibleForTesting
  ModelStore<VerifiedPiperModelBundle> get modelStore => _modelStore;

  @override
  Future<AppResult<void>> speak(String text) {
    final utterance = text.trim();
    if (_closed) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'piper_speech_closed'),
        ),
      );
    }
    if (utterance.isEmpty) {
      return Future.value(
        const AppError(
          ValidationFailure(code: 'piper_speech_empty_text'),
        ),
      );
    }
    if (_active != null || _stopTask != null) {
      return Future.value(
        const AppError(
          DeviceUnavailableFailure(code: 'piper_speech_busy'),
        ),
      );
    }

    final operation = _PiperSpeechOperation();
    _active = operation;
    unawaited(_run(operation, utterance));
    return operation.completion.future;
  }

  Future<void> _run(_PiperSpeechOperation operation, String text) async {
    AppResult<void> result;
    try {
      final preparation = await _modelStore.prepare();
      if (_isCancelled(operation)) {
        result = const AppSuccess<void>(null);
      } else {
        switch (preparation) {
          case AppError<VerifiedPiperModelBundle>(:final failure):
            result = AppError(failure);
          case AppSuccess<VerifiedPiperModelBundle>(:final value):
            result = await _synthesizeThenPlay(operation, text, value);
        }
      }
    } on Object catch (error, stackTrace) {
      result = AppError(
        DeviceUnavailableFailure(
          code: 'piper_speech_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    if (_isCancelled(operation)) {
      result = const AppSuccess<void>(null);
    }
    if (identical(_active, operation)) _active = null;
    if (!operation.completion.isCompleted) {
      operation.completion.complete(result);
    }
  }

  Future<AppResult<void>> _synthesizeThenPlay(
    _PiperSpeechOperation operation,
    String text,
    VerifiedPiperModelBundle bundle,
  ) async {
    GeneratedSpeechAudio audio;
    _synthesisAttempts += 1;
    try {
      final generation = await _generator.generate(
        text: text,
        bundle: bundle,
        configuration: _configuration,
        onRuntimeCreated: (createdAtUtc) {
          _lastNativeRuntimeCreatedAtUtc = createdAtUtc;
          _lastNativeRuntimeFreedAtUtc = null;
          _nativeRuntimeActive = true;
        },
        onRuntimeFreed: (freedAtUtc) {
          _lastNativeRuntimeFreedAtUtc = freedAtUtc;
          _nativeRuntimeActive = false;
        },
      );
      _lastNativeRuntimeCreatedAtUtc = generation.runtimeCreatedAtUtc;
      _lastNativeRuntimeFreedAtUtc = generation.runtimeFreedAtUtc;
      _nativeRuntimeActive = false;
      audio = generation.audio;
    } on Object catch (error, stackTrace) {
      return AppError(
        DeviceUnavailableFailure(
          code: 'piper_synthesis_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      _synthesisSettlements += 1;
    }

    if (_isCancelled(operation)) return const AppSuccess<void>(null);
    final validation = _validateAudio(audio);
    if (validation case AppError<void>()) return validation;

    final playback = await _audioPlayer.play(audio);
    if (_isCancelled(operation)) return const AppSuccess<void>(null);
    if (playback is AppSuccess<void>) _completedPlaybacks += 1;
    return playback;
  }

  AppResult<void> _validateAudio(GeneratedSpeechAudio audio) {
    if (audio.sampleRateHz <= 0 || audio.samples.isEmpty) {
      return const AppError(
        ValidationFailure(
          code: 'piper_synthesis_invalid_audio',
          message: 'Piper returned no playable PCM samples.',
        ),
      );
    }

    var peak = 0.0;
    for (final sample in audio.samples) {
      if (!sample.isFinite) {
        return const AppError(
          ValidationFailure(
            code: 'piper_synthesis_invalid_audio',
            message: 'Piper returned a non-finite PCM sample.',
          ),
        );
      }
      final magnitude = sample.abs();
      if (magnitude > peak) peak = magnitude;
    }
    if (peak <= 0) {
      return const AppError(
        ValidationFailure(
          code: 'piper_synthesis_invalid_audio',
          message: 'Piper returned silent PCM.',
        ),
      );
    }

    _lastSampleCount = audio.samples.length;
    _lastSampleRateHz = audio.sampleRateHz;
    _lastPeakAmplitude = peak;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> stop() {
    final existing = _stopTask;
    if (existing != null) return existing;

    late final Future<AppResult<void>> task;
    task = _stopOnce().whenComplete(() {
      if (identical(_stopTask, task)) _stopTask = null;
    });
    _stopTask = task;
    return task;
  }

  Future<AppResult<void>> _stopOnce() async {
    final operation = _active;
    operation?.cancelled = true;
    AppFailure? firstFailure;

    Future<void> settleResult(Future<AppResult<void>> task) async {
      final result = await task;
      if (result case AppError<void>(:final failure)) {
        firstFailure ??= failure;
      }
    }

    Future<void> suspendStore() async {
      try {
        await _modelStore.suspend();
      } on Object catch (error, stackTrace) {
        firstFailure ??= DeviceUnavailableFailure(
          code: 'piper_model_suspend_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        );
      }
    }

    await Future.wait<void>([
      settleResult(_audioPlayer.stop()),
      if (operation != null) suspendStore(),
    ]);
    if (operation != null) await operation.completion.future;
    final failure = firstFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  @override
  Future<AppResult<void>> close() {
    final existing = _closeTask;
    if (existing != null) return existing;

    _closed = true;
    _active?.cancelled = true;
    late final Future<AppResult<void>> task;
    task = _closeOnce().then((result) {
      if (result is AppError<void> && identical(_closeTask, task)) {
        _closeTask = null;
      }
      return result;
    });
    _closeTask = task;
    return task;
  }

  Future<AppResult<void>> _closeOnce() async {
    final operation = _active;
    AppFailure? firstFailure;

    Future<void> closePlayer() async {
      final result = await _audioPlayer.close();
      if (result case AppError<void>(:final failure)) {
        firstFailure ??= failure;
      }
    }

    Future<void> closeStore() async {
      try {
        await _modelStore.close();
      } on Object catch (error, stackTrace) {
        firstFailure ??= DeviceUnavailableFailure(
          code: 'piper_model_close_failed',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        );
      }
    }

    await Future.wait<void>([closePlayer(), closeStore()]);
    if (operation != null) await operation.completion.future;
    final failure = firstFailure;
    return failure == null ? const AppSuccess<void>(null) : AppError<void>(failure);
  }

  bool _isCancelled(_PiperSpeechOperation operation) {
    return operation.cancelled || _closed || !identical(_active, operation);
  }
}

/// Whether a local Piper failure happened before any audio could be heard.
bool isPiperFallbackEligible(AppFailure failure) {
  return switch (failure.code) {
    'model_insufficient_storage' ||
    'model_integrity' ||
    'model_download_unauthorized' ||
    'model_artifact_not_found' ||
    'model_host_response' ||
    'model_download' ||
    'model_cache_io' ||
    'model_storage_unavailable' ||
    'model_store_unexpected' ||
    'piper_synthesis_failed' ||
    'piper_synthesis_invalid_audio' ||
    'local_speech_audio_invalid' ||
    'local_speech_playback_start_failed' => true,
    // Unknown failures are deliberately unsafe. A future adapter error may
    // arise after native output begins, so it must be reviewed and explicitly
    // added above before system speech is allowed to repeat the utterance.
    _ => false,
  };
}

final class _PiperSpeechOperation {
  final Completer<AppResult<void>> completion = Completer<AppResult<void>>();
  bool cancelled = false;
}
