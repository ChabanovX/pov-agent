import 'dart:async';
import 'dart:typed_data';

import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';
import 'package:record/record.dart';

const _monoChannelCount = 1;
const _pcm16BytesPerSample = 2;
const _targetChunkDurationMilliseconds = 100;

/// Narrow backend around `record` that keeps plugin types inside data.
abstract interface class MicrophoneRecorderBackend {
  /// Whether this device can stream raw PCM16.
  Future<bool> supportsPcm16Stream();

  /// Starts in-memory mono PCM16 capture.
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRateHz,
    required int streamBufferBytes,
  });

  /// Stops active capture.
  Future<void> stop();

  /// Releases the native recorder.
  Future<void> close();
}

/// Production `record` backend that never opens a file recording path.
final class RecordMicrophoneRecorderBackend implements MicrophoneRecorderBackend {
  /// Creates a backend around an optional recorder test seam.
  RecordMicrophoneRecorderBackend({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> supportsPcm16Stream() {
    return _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
  }

  @override
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRateHz,
    required int streamBufferBytes,
  }) {
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRateHz,
        numChannels: _monoChannelCount,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        streamBufferSize: streamBufferBytes,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> close() => _recorder.dispose();
}

/// Streams microphone PCM to ASR without creating a temporary audio file.
///
/// Startup reserves the single capture slot before its first platform await.
/// Stop and close settle an in-flight startup before tearing it down, and join
/// concurrent calls. A failed native operation retains ownership so cleanup
/// can be retried. Stream forwarding makes native stream completion part of the
/// stop boundary instead of racing the recognizer's final drain. Once close
/// begins, startup remains terminal even when native release needs a retry.
final class RecordMicrophoneAudioSource implements MicrophoneAudioSource {
  /// Creates a microphone source around the production or a test backend.
  RecordMicrophoneAudioSource({MicrophoneRecorderBackend? backend})
    : _backend = backend ?? RecordMicrophoneRecorderBackend();

  final MicrophoneRecorderBackend _backend;

  StreamController<Uint8List>? _activeController;
  // Subscription ownership spans start through retryable stop/close.
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _activeSubscription;
  Future<Stream<Uint8List>>? _startTask;
  Future<void>? _stopTask;
  Future<void>? _closeTask;
  var _nativeCaptureMayBeOwned = false;
  var _closeRequested = false;
  var _closed = false;

  @override
  Future<Stream<Uint8List>> start({required int sampleRateHz}) {
    if (_closeRequested) {
      return Future.error(
        const MicrophoneCaptureException(
          code: 'microphone_capture_closed',
          message: 'The microphone source is closed.',
        ),
      );
    }
    if (sampleRateHz <= 0) {
      return Future.error(
        const MicrophoneCaptureException(
          code: 'microphone_capture_invalid_sample_rate',
          message: 'The requested sample rate must be positive.',
        ),
      );
    }
    if (_startTask != null || _hasCaptureOwnership || _stopTask != null) {
      return Future.error(
        const MicrophoneCaptureException(
          code: 'microphone_capture_busy',
          message: 'A microphone capture is already active.',
        ),
      );
    }

    late final Future<Stream<Uint8List>> task;
    task = _startOnce(sampleRateHz).whenComplete(() {
      if (identical(_startTask, task)) _startTask = null;
    });
    _startTask = task;
    return task;
  }

  Future<Stream<Uint8List>> _startOnce(int sampleRateHz) async {
    if (!await _backend.supportsPcm16Stream()) {
      throw const MicrophoneCaptureException(
        code: 'microphone_pcm16_unsupported',
        message: 'This device cannot stream PCM16 microphone audio.',
      );
    }

    late final Stream<Uint8List> rawStream;
    _nativeCaptureMayBeOwned = true;
    try {
      rawStream = await _backend.startPcm16Stream(
        sampleRateHz: sampleRateHz,
        streamBufferBytes: _streamBufferByteCount(sampleRateHz),
      );
    } on Object catch (startError, startStackTrace) {
      // A platform channel may fail after native capture was allocated but
      // before it returns a Dart stream. Stop is the only safe rollback.
      try {
        await _backend.stop();
        _nativeCaptureMayBeOwned = false;
      } on Object catch (cleanupError, cleanupStackTrace) {
        Error.throwWithStackTrace(cleanupError, cleanupStackTrace);
      }
      Error.throwWithStackTrace(startError, startStackTrace);
    }
    final controller = StreamController<Uint8List>();
    _activeController = controller;
    _activeSubscription = rawStream.listen(
      controller.add,
      onError: controller.addError,
      onDone: () => unawaited(controller.close()),
    );
    return controller.stream;
  }

  @override
  Future<void> stop() {
    final activeTask = _stopTask;
    if (activeTask != null) return activeTask;
    final pendingStart = _startTask;
    if (pendingStart == null && !_hasCaptureOwnership) {
      return Future<void>.value();
    }

    late final Future<void> task;
    task = _settleStartupAndStop(pendingStart).whenComplete(() {
      if (identical(_stopTask, task)) _stopTask = null;
    });
    _stopTask = task;
    return task;
  }

  Future<void> _settleStartupAndStop(
    Future<Stream<Uint8List>>? pendingStart,
  ) async {
    if (pendingStart != null) {
      try {
        await pendingStart;
      } on Object {
        // The start caller owns its failure. Stop still retries any native
        // ownership left behind by a failed startup rollback.
      }
    }
    await _stopActiveCapture();
  }

  Future<void> _stopActiveCapture() async {
    final subscription = _activeSubscription;
    final controller = _activeController;
    if (_nativeCaptureMayBeOwned) {
      await _backend.stop();
      _nativeCaptureMayBeOwned = false;
    }
    await subscription?.cancel();
    if (controller != null && !controller.isClosed) await controller.close();
    if (identical(_activeSubscription, subscription)) {
      _activeSubscription = null;
    }
    if (identical(_activeController, controller)) _activeController = null;
  }

  @override
  Future<void> close() {
    if (_closed) return Future<void>.value();
    final activeTask = _closeTask;
    if (activeTask != null) return activeTask;
    _closeRequested = true;

    late final Future<void> task;
    task = _closeOnce().whenComplete(() {
      if (identical(_closeTask, task)) _closeTask = null;
    });
    _closeTask = task;
    return task;
  }

  Future<void> _closeOnce() async {
    await stop();
    await _backend.close();
    _closed = true;
  }

  bool get _hasCaptureOwnership => _nativeCaptureMayBeOwned || _activeController != null || _activeSubscription != null;
}

int _streamBufferByteCount(int sampleRateHz) {
  return sampleRateHz * _pcm16BytesPerSample * _targetChunkDurationMilliseconds ~/ Duration.millisecondsPerSecond;
}
