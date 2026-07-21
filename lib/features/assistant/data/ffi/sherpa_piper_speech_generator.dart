import 'dart:isolate';
import 'dart:typed_data';

import 'package:pov_agent/features/assistant/application/models/piper_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/data/ffi/piper_speech_generator.dart';
import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _eventRuntimeCreated = 0;
const _eventRuntimeFreed = 1;
const _eventGenerationCompleted = 2;
const _eventGenerationFailed = 3;

typedef _PiperWorkerRequest = ({
  SendPort events,
  String text,
  VerifiedPiperModelBundle bundle,
  PiperRuntimeConfiguration configuration,
});

/// Runs synchronous sherpa-onnx VITS synthesis on a short-lived isolate.
///
/// Every request initializes, uses, and frees its native runtime on the same
/// isolate. Creation, free, and completion travel through one event port in
/// that order. The returned PCM is transferred only after `OfflineTts.free()`,
/// so Piper model memory is gone before foreground playback starts beside YOLO
/// and Qwen. Native generation of one short sentence is non-preemptible;
/// callers invalidate its result on stop and await this boundary until free
/// completes.
final class SherpaPiperSpeechGenerator implements PiperSpeechGenerator {
  /// Creates the production sherpa-onnx generator.
  const SherpaPiperSpeechGenerator();

  @override
  Future<PiperSpeechGeneration> generate({
    required String text,
    required VerifiedPiperModelBundle bundle,
    required PiperRuntimeConfiguration configuration,
    required void Function(DateTime createdAtUtc) onRuntimeCreated,
    required void Function(DateTime freedAtUtc) onRuntimeFreed,
  }) async {
    final events = ReceivePort();
    Isolate? worker;
    var terminalEventReceived = false;
    try {
      worker = await Isolate.spawn<_PiperWorkerRequest>(
        _generateOnWorker,
        (
          events: events.sendPort,
          text: text,
          bundle: bundle,
          configuration: configuration,
        ),
        debugName: 'pov-piper-synthesis',
        onError: events.sendPort,
        onExit: events.sendPort,
      );

      await for (final event in events) {
        switch (event) {
          case [_eventRuntimeCreated, final int microsecondsSinceEpoch]:
            onRuntimeCreated(_utcTimestamp(microsecondsSinceEpoch));
          case [_eventRuntimeFreed, final int microsecondsSinceEpoch]:
            onRuntimeFreed(_utcTimestamp(microsecondsSinceEpoch));
          case [
            _eventGenerationCompleted,
            final TransferableTypedData transferred,
            final int sampleRate,
            final int createdAtMicroseconds,
            final int freedAtMicroseconds,
          ]:
            terminalEventReceived = true;
            final bytes = transferred.materialize().asUint8List();
            final samples = Float32List.view(
              bytes.buffer,
              bytes.offsetInBytes,
              bytes.lengthInBytes ~/ Float32List.bytesPerElement,
            );
            return PiperSpeechGeneration(
              audio: GeneratedSpeechAudio(
                samples: samples,
                sampleRateHz: sampleRate,
              ),
              runtimeCreatedAtUtc: _utcTimestamp(createdAtMicroseconds),
              runtimeFreedAtUtc: _utcTimestamp(freedAtMicroseconds),
            );
          case [
            _eventGenerationFailed,
            final String description,
            final String workerStackTrace,
          ]:
            terminalEventReceived = true;
            Error.throwWithStackTrace(
              StateError(description),
              StackTrace.fromString(workerStackTrace),
            );
          case [final String description, final String workerStackTrace]:
            terminalEventReceived = true;
            Error.throwWithStackTrace(
              StateError('Piper worker isolate failed: $description'),
              StackTrace.fromString(workerStackTrace),
            );
          case null:
            terminalEventReceived = true;
            throw StateError(
              'Piper worker isolate exited without a terminal event.',
            );
          case final Object unexpected:
            terminalEventReceived = true;
            throw StateError(
              'Piper worker returned an unexpected event: $unexpected',
            );
        }
      }
      throw StateError('Piper worker event port closed before completion.');
    } finally {
      if (!terminalEventReceived) {
        worker?.kill(priority: Isolate.immediate);
      }
      events.close();
    }
  }
}

DateTime _utcTimestamp(int microsecondsSinceEpoch) {
  return DateTime.fromMicrosecondsSinceEpoch(
    microsecondsSinceEpoch,
    isUtc: true,
  );
}

void _generateOnWorker(_PiperWorkerRequest request) {
  final (
    :events,
    :text,
    :bundle,
    :configuration,
  ) = request;

  sherpa.OfflineTts? runtime;
  TransferableTypedData? transferredSamples;
  int? sampleRate;
  int? createdAtMicroseconds;
  int? freedAtMicroseconds;
  Object? failure;
  StackTrace? failureStackTrace;

  try {
    sherpa.initBindings();
    runtime = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: bundle.modelFilePath,
            tokens: bundle.tokensFilePath,
            dataDir: bundle.espeakDataDirectoryPath,
            noiseScale: configuration.noiseScale,
            noiseScaleW: configuration.noiseScaleW,
            lengthScale: configuration.lengthScale,
          ),
          numThreads: configuration.threadCount,
          debug: configuration.debug,
          provider: configuration.provider,
        ),
        maxNumSenetences: configuration.maxSentences,
        silenceScale: configuration.silenceScale,
      ),
    );
    createdAtMicroseconds = DateTime.now().toUtc().microsecondsSinceEpoch;
    events.send([_eventRuntimeCreated, createdAtMicroseconds]);

    final generated = runtime.generateWithConfig(
      text: text,
      config: sherpa.OfflineTtsGenerationConfig(
        silenceScale: configuration.silenceScale,
        speed: configuration.speed,
        sid: configuration.speakerId,
      ),
    );
    final bytes = Uint8List.view(
      generated.samples.buffer,
      generated.samples.offsetInBytes,
      generated.samples.lengthInBytes,
    );
    transferredSamples = TransferableTypedData.fromList([bytes]);
    sampleRate = generated.sampleRate;
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStackTrace = stackTrace;
  }

  if (runtime != null) {
    try {
      runtime.free();
      freedAtMicroseconds = DateTime.now().toUtc().microsecondsSinceEpoch;
      events.send([_eventRuntimeFreed, freedAtMicroseconds]);
    } on Object catch (error, stackTrace) {
      final generationFailure = failure;
      failure = StateError(
        generationFailure == null
            ? 'OfflineTts.free() failed: $error'
            : 'Piper generation failed ($generationFailure), then '
                  'OfflineTts.free() also failed: $error',
      );
      failureStackTrace = stackTrace;
    }
  }

  final terminalFailure = failure;
  if (terminalFailure != null) {
    events.send([
      _eventGenerationFailed,
      terminalFailure.toString(),
      failureStackTrace.toString(),
    ]);
    return;
  }

  final samples = transferredSamples;
  final rate = sampleRate;
  final createdAt = createdAtMicroseconds;
  final freedAt = freedAtMicroseconds;
  if (samples == null || rate == null || createdAt == null || freedAt == null) {
    events.send([
      _eventGenerationFailed,
      'Piper worker completed without audio or a native lifecycle interval.',
      StackTrace.current.toString(),
    ]);
    return;
  }
  events.send([
    _eventGenerationCompleted,
    samples,
    rate,
    createdAt,
    freedAt,
  ]);
}
