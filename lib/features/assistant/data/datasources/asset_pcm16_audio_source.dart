import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pov_agent/features/assistant/data/datasources/microphone_audio_source.dart';

/// Waits between consecutive recorded-audio chunks.
typedef RecordedAudioChunkDelay = Future<void> Function(Duration duration);

/// Replays one bundled PCM16 command through the production ASR boundary.
///
/// This source exists only for deterministic simulator and device acceptance.
/// Its first capture emits the fixture at real-time cadence and remains open
/// until recognition stops it. Later captures stay silent, preventing the
/// same command from triggering an unbounded answer/re-arm loop.
final class AssetPcm16AudioSource implements MicrophoneAudioSource {
  /// Creates a one-shot source for raw mono PCM16 [assetPath].
  factory AssetPcm16AudioSource({
    required AssetBundle assetBundle,
    required String assetPath,
    required int sampleRateHz,
    Duration chunkDuration = const Duration(milliseconds: 100),
    RecordedAudioChunkDelay delay = Future<void>.delayed,
  }) {
    if (assetPath.trim().isEmpty) {
      throw ArgumentError.value(assetPath, 'assetPath', 'must not be empty');
    }
    if (sampleRateHz <= 0) {
      throw ArgumentError.value(
        sampleRateHz,
        'sampleRateHz',
        'must be positive',
      );
    }
    if (chunkDuration <= Duration.zero) {
      throw ArgumentError.value(
        chunkDuration,
        'chunkDuration',
        'must be positive',
      );
    }
    return AssetPcm16AudioSource._(
      assetBundle,
      assetPath,
      sampleRateHz,
      chunkDuration,
      delay,
    );
  }

  AssetPcm16AudioSource._(
    this._assetBundle,
    this._assetPath,
    this._sampleRateHz,
    this._chunkDuration,
    this._delay,
  );

  static const _pcm16BytesPerSample = 2;

  final AssetBundle _assetBundle;
  final String _assetPath;
  final int _sampleRateHz;
  final Duration _chunkDuration;
  final RecordedAudioChunkDelay _delay;

  StreamController<Uint8List>? _controller;
  Future<void>? _pumpTask;
  Future<void>? _stopTask;
  var _fixtureConsumed = false;
  var _epoch = 0;
  var _closed = false;

  @override
  Future<Stream<Uint8List>> start({required int sampleRateHz}) async {
    if (_closed) {
      throw const MicrophoneCaptureException(
        code: 'recorded_audio_source_closed',
        message: 'The recorded-audio acceptance source is closed.',
      );
    }
    if (_controller != null || _stopTask != null) {
      throw const MicrophoneCaptureException(
        code: 'recorded_audio_source_busy',
        message: 'A recorded-audio capture is already active.',
      );
    }
    if (sampleRateHz != _sampleRateHz) {
      throw MicrophoneCaptureException(
        code: 'recorded_audio_sample_rate_mismatch',
        message: 'Expected $_sampleRateHz Hz PCM, received $sampleRateHz Hz.',
      );
    }

    final controller = StreamController<Uint8List>.broadcast();
    _controller = controller;
    final epoch = ++_epoch;
    if (!_fixtureConsumed) {
      late final Uint8List data;
      try {
        data = await _loadFixture();
      } on Object {
        if (identical(_controller, controller)) _controller = null;
        await controller.close();
        rethrow;
      }
      if (_controller != controller || epoch != _epoch || _closed) {
        await controller.close();
        throw const MicrophoneCaptureException(
          code: 'recorded_audio_start_cancelled',
          message: 'Recorded-audio startup was cancelled.',
        );
      }
      _fixtureConsumed = true;
      // Defer the first chunk until the recognizer has attached its listener.
      _pumpTask = Future<void>(() => _pump(controller, data, epoch));
    }
    return controller.stream;
  }

  Future<Uint8List> _loadFixture() async {
    try {
      final data = await _assetBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.isEmpty || bytes.length.isOdd) {
        throw const MicrophoneCaptureException(
          code: 'recorded_audio_invalid_pcm16',
          message: 'The recorded-audio fixture must contain complete samples.',
        );
      }
      return Uint8List.fromList(bytes);
    } on MicrophoneCaptureException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        MicrophoneCaptureException(
          code: 'recorded_audio_asset_load_failed',
          message: 'Could not load $_assetPath.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  Future<void> _pump(
    StreamController<Uint8List> controller,
    Uint8List bytes,
    int epoch,
  ) async {
    final chunkByteCount =
        _sampleRateHz * _pcm16BytesPerSample * _chunkDuration.inMicroseconds ~/ Duration.microsecondsPerSecond;
    for (var offset = 0; offset < bytes.length; offset += chunkByteCount) {
      if (_controller != controller || epoch != _epoch || _closed) return;
      final candidateEnd = offset + chunkByteCount;
      final end = candidateEnd < bytes.length ? candidateEnd : bytes.length;
      controller.add(Uint8List.sublistView(bytes, offset, end));
      await _delay(_chunkDuration);
    }
  }

  @override
  Future<void> stop() {
    final activeTask = _stopTask;
    if (activeTask != null) return activeTask;
    if (_controller == null) return Future<void>.value();

    late final Future<void> task;
    task = _stopOnce().whenComplete(() {
      if (identical(_stopTask, task)) _stopTask = null;
    });
    _stopTask = task;
    return task;
  }

  Future<void> _stopOnce() async {
    _epoch += 1;
    final controller = _controller;
    final pumpTask = _pumpTask;
    _controller = null;
    _pumpTask = null;
    await pumpTask;
    if (controller != null && !controller.isClosed) await controller.close();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await stop();
    _closed = true;
  }
}
