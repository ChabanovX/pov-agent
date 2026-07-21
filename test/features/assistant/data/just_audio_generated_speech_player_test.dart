import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/adapters/just_audio_generated_speech_player.dart';
import 'package:pov_agent/features/assistant/data/datasources/just_audio_playback_backend.dart';
import 'package:pov_agent/features/assistant/data/mappers/pcm16_wav_encoder.dart';
import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  group('Pcm16WavEncoder', () {
    test('writes a mono 16-bit WAV header and clips endpoint samples', () {
      final bytes = Pcm16WavEncoder.encode(
        GeneratedSpeechAudio(
          samples: const [-2, -1, -0.5, 0, 0.5, 1, 2],
          sampleRateHz: 22050,
        ),
      );
      final data = ByteData.sublistView(bytes);

      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
      expect(data.getUint32(4, Endian.little), bytes.length - 8);
      expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(bytes.sublist(12, 16)), 'fmt ');
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 22050);
      expect(data.getUint32(28, Endian.little), 44100);
      expect(data.getUint16(34, Endian.little), 16);
      expect(ascii.decode(bytes.sublist(36, 40)), 'data');
      expect(data.getUint32(40, Endian.little), 14);
      expect(
        [
          for (var offset = 44; offset < bytes.length; offset += 2) data.getInt16(offset, Endian.little),
        ],
        [-32768, -32768, -16384, 0, 16384, 32767, 32767],
      );
    });

    test('rejects non-finite PCM before native playback', () {
      final audio = GeneratedSpeechAudio(
        samples: const [double.nan],
        sampleRateHz: 22050,
      );

      expect(() => Pcm16WavEncoder.encode(audio), throwsArgumentError);
    });
  });

  group('JustAudioGeneratedSpeechPlayer', () {
    late _FakeJustAudioPlaybackBackend backend;
    late JustAudioGeneratedSpeechPlayer player;

    setUp(() {
      backend = _FakeJustAudioPlaybackBackend();
      player = JustAudioGeneratedSpeechPlayer(
        backend: backend,
        commandTimeout: const Duration(milliseconds: 100),
        playbackGracePeriod: const Duration(milliseconds: 100),
      );
    });

    tearDown(() async {
      backend.releaseErrors.clear();
      backend.closeError = null;
      await player.close();
    });

    test('plays an in-memory WAV through natural completion', () async {
      final result = await player.play(_audio());

      expect(result, isA<AppSuccess<void>>());
      expect(
        backend.events,
        ['configure', 'load', 'activate', 'play', 'release'],
      );
      expect(backend.loadedBytes, isNotNull);
      expect(ascii.decode(backend.loadedBytes!.sublist(0, 4)), 'RIFF');
      expect(player.playbackProbe.isPlaying, isFalse);
      expect(player.playbackProbe.startedCount, 1);
      expect(player.playbackProbe.completedCount, 1);
      expect(player.playbackProbe.stoppedCount, 0);
      expect(player.playbackProbe.failedCount, 0);
    });

    test('reports load rejection as a pre-start failure', () async {
      backend.loadError = StateError('decoder rejected WAV');

      final result = await player.play(_audio());

      expect(result, _failureWithCode('local_speech_playback_start_failed'));
      expect(backend.events, ['configure', 'load', 'release']);
      expect(player.playbackProbe.startedCount, 0);
      expect(player.playbackProbe.failedCount, 1);
    });

    test('does not expose fallback eligibility when cleanup fails', () async {
      backend
        ..loadError = StateError('decoder rejected WAV')
        ..releaseErrors.add(StateError('native release failed'));

      final result = await player.play(_audio());

      expect(result, _failureWithCode('local_speech_playback_cleanup_failed'));
      expect(player.playbackProbe.startedCount, 0);
      expect(player.playbackProbe.failedCount, 1);
    });

    test('treats failure after play dispatch as potentially audible', () async {
      backend.playErrorBeforeStart = StateError('native start rejected');

      final result = await player.play(_audio());

      expect(result, _failureWithCode('local_speech_playback_failed'));
      expect(player.playbackProbe.startedCount, 0);
      expect(player.playbackProbe.failedCount, 1);
    });

    test('distinguishes failure after native playback started', () async {
      backend.playErrorAfterStart = StateError('audio route disappeared');

      final result = await player.play(_audio());

      expect(result, _failureWithCode('local_speech_playback_failed'));
      expect(player.playbackProbe.startedCount, 1);
      expect(player.playbackProbe.failedCount, 1);
      expect(player.playbackProbe.isPlaying, isFalse);
    });

    test('rejects invalid PCM without touching the native backend', () async {
      final result = await player.play(
        GeneratedSpeechAudio(
          samples: const [double.infinity],
          sampleRateHz: 22050,
        ),
      );

      expect(result, _failureWithCode('local_speech_audio_invalid'));
      expect(backend.events, isEmpty);
    });

    test('stop interrupts active playback without failing the utterance', () async {
      backend.holdPlayback = true;
      final speech = player.play(_audio());
      await _waitFor(() => player.playbackProbe.isPlaying);

      final stopped = await player.stop();

      expect(stopped, isA<AppSuccess<void>>());
      expect(await speech, isA<AppSuccess<void>>());
      expect(player.playbackProbe.isPlaying, isFalse);
      expect(player.playbackProbe.startedCount, 1);
      expect(player.playbackProbe.completedCount, 0);
      expect(player.playbackProbe.stoppedCount, 1);
      expect(player.playbackProbe.failedCount, 0);
    });

    test('stop reports cleanup failure but keeps play as cancellation', () async {
      backend
        ..holdPlayback = true
        ..releaseErrors.addAll([
          StateError('first release failed'),
          StateError('final release failed'),
        ]);
      final speech = player.play(_audio());
      await _waitFor(() => player.playbackProbe.isPlaying);

      final stopped = await player.stop();

      expect(stopped, _failureWithCode('local_speech_playback_stop_failed'));
      expect(await speech, isA<AppSuccess<void>>());
      expect(player.playbackProbe.stoppedCount, 1);
      expect(player.playbackProbe.failedCount, 0);
    });

    test('stop fails rather than claiming a pending activation is quiescent', () async {
      final activationGate = backend.activationGate = Completer<void>();
      final speech = player.play(_audio());
      await _waitFor(() => backend.events.contains('activate'));

      final stopped = await player.stop();

      expect(stopped, _failureWithCode('local_speech_playback_stop_failed'));
      activationGate.complete();
      expect(await speech, isA<AppSuccess<void>>());
      expect(player.playbackProbe.failedCount, 0);
    });

    test('rejects overlap instead of queuing a second utterance', () async {
      backend.holdPlayback = true;
      final first = player.play(_audio());
      await _waitFor(() => player.playbackProbe.isPlaying);

      final second = await player.play(_audio());

      expect(second, _failureWithCode('local_speech_playback_busy'));
      expect(backend.events.where((event) => event == 'play'), hasLength(1));
      await player.stop();
      expect(await first, isA<AppSuccess<void>>());
    });

    test('close stops playback, rejects new work, and is idempotent', () async {
      backend.holdPlayback = true;
      final speech = player.play(_audio());
      await _waitFor(() => player.playbackProbe.isPlaying);

      final firstClose = await player.close();
      final secondClose = await player.close();
      final rejected = await player.play(_audio());

      expect(firstClose, isA<AppSuccess<void>>());
      expect(secondClose, isA<AppSuccess<void>>());
      expect(await speech, isA<AppSuccess<void>>());
      expect(rejected, _failureWithCode('local_speech_player_closed'));
      expect(backend.closeCalls, 1);
    });
  });

  test('iOS release waits for late activation before deactivating', () async {
    final session = _GatedAudioSessionBackend();
    final backend = PluginJustAudioPlaybackBackend(
      targetPlatform: TargetPlatform.iOS,
      audioSessionBackend: session,
      iosReleaseRetryDelay: Duration.zero,
    );
    await backend.configureSpeechMixing();

    final activation = backend.activate();
    await _waitFor(() => session.activationRequests == 1);
    var releaseSettled = false;
    final release = backend.release().whenComplete(() {
      releaseSettled = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(releaseSettled, isFalse);
    expect(session.deactivationRequests, 0);
    session.activationGate.complete();
    await activation;
    await release;

    expect(session.deactivationRequests, 1);
    expect(session.active, isFalse);
    await backend.close();
  });
}

GeneratedSpeechAudio _audio() => GeneratedSpeechAudio(
  samples: const [0, 0.25, -0.25, 0],
  sampleRateHz: 22050,
);

Matcher _failureWithCode(String code) => isA<AppError<void>>().having(
  (result) => result.failure.code,
  'failure code',
  code,
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached.');
}

final class _FakeJustAudioPlaybackBackend implements JustAudioPlaybackBackend {
  final List<String> events = [];
  final List<Error> releaseErrors = [];
  Uint8List? loadedBytes;
  Error? loadError;
  Error? playErrorBeforeStart;
  Error? playErrorAfterStart;
  Error? closeError;
  bool holdPlayback = false;
  Completer<void>? activationGate;
  Completer<void>? playbackGate;
  int closeCalls = 0;

  @override
  Future<void> configureSpeechMixing() async {
    events.add('configure');
  }

  @override
  Future<void> load(Uint8List wavBytes) async {
    events.add('load');
    if (loadError case final error?) throw error;
    loadedBytes = Uint8List.fromList(wavBytes);
  }

  @override
  Future<void> activate() async {
    events.add('activate');
    final gate = activationGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> play({required VoidCallback onStarted}) async {
    events.add('play');
    if (playErrorBeforeStart case final error?) throw error;
    onStarted();
    if (playErrorAfterStart case final error?) throw error;
    if (!holdPlayback) return;
    final gate = playbackGate = Completer<void>();
    await gate.future;
  }

  @override
  Future<void> release() async {
    events.add('release');
    final gate = playbackGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    if (releaseErrors.isNotEmpty) throw releaseErrors.removeAt(0);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    events.add('close');
    if (closeError case final error?) throw error;
  }
}

final class _GatedAudioSessionBackend implements JustAudioSessionBackend {
  final Completer<void> activationGate = Completer<void>();
  int activationRequests = 0;
  int deactivationRequests = 0;
  bool active = false;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}

  @override
  Future<bool> setActive({required bool active}) async {
    if (active) {
      activationRequests += 1;
      await activationGate.future;
    } else {
      deactivationRequests += 1;
    }
    this.active = active;
    return true;
  }
}
