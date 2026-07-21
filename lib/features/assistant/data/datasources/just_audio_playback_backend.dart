import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Process-wide audio-session commands used by generated speech.
///
/// The seam makes activation/release ordering testable without invoking a
/// platform channel. Production still delegates to audio_session's singleton.
abstract interface class JustAudioSessionBackend {
  /// Applies the supplied speech mixing policy.
  Future<void> configure(AudioSessionConfiguration configuration);

  /// Requests activation or deactivation and reports whether native accepted it.
  Future<bool> setActive({required bool active});
}

/// audio_session implementation of [JustAudioSessionBackend].
final class PluginJustAudioSessionBackend implements JustAudioSessionBackend {
  AudioSession? _session;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    final session = _session ??= await AudioSession.instance;
    await session.configure(configuration);
  }

  @override
  Future<bool> setActive({required bool active}) async {
    final session = _session ??= await AudioSession.instance;
    return session.setActive(active);
  }
}

/// The native operations required by generated speech playback.
///
/// This narrow seam keeps lifecycle and failure-stage tests independent of
/// method channels while production remains backed by `just_audio`.
abstract interface class JustAudioPlaybackBackend {
  /// Applies the foreground speech policy before an utterance is loaded.
  Future<void> configureSpeechMixing();

  /// Loads a complete in-memory WAV stream into a fresh native player.
  Future<void> load(Uint8List wavBytes);

  /// Activates the iOS session; Android intentionally keeps unmanaged focus.
  Future<void> activate();

  /// Plays to natural completion and reports when native playback starts.
  Future<void> play({required VoidCallback onStarted});

  /// Interrupts playback and releases all per-utterance resources.
  Future<void> release();

  /// Permanently releases the backend.
  Future<void> close();
}

/// `just_audio` implementation used by local generated speech.
final class PluginJustAudioPlaybackBackend implements JustAudioPlaybackBackend {
  /// Creates a reusable backend that owns one player at a time.
  PluginJustAudioPlaybackBackend({
    TargetPlatform? targetPlatform,
    JustAudioSessionBackend? audioSessionBackend,
    Duration iosReleaseRetryDelay = const Duration(milliseconds: 50),
    int iosReleaseAttempts = 4,
  }) : assert(
         !iosReleaseRetryDelay.isNegative,
         'The iOS release retry delay cannot be negative.',
       ),
       assert(
         iosReleaseAttempts > 0,
         'The iOS release attempt count must be positive.',
       ),
       _targetPlatform = targetPlatform ?? defaultTargetPlatform,
       _audioSessionBackend = audioSessionBackend ?? PluginJustAudioSessionBackend(),
       _iosReleaseRetryDelay = iosReleaseRetryDelay,
       _iosReleaseAttempts = iosReleaseAttempts;

  static const _speechMixingConfiguration = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    avAudioSessionMode: AVAudioSessionMode.voicePrompt,
    avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
    androidWillPauseWhenDucked: false,
  );

  final TargetPlatform _targetPlatform;
  final JustAudioSessionBackend _audioSessionBackend;
  final Duration _iosReleaseRetryDelay;
  final int _iosReleaseAttempts;

  AudioPlayer? _player;
  Future<void>? _activationTask;
  Future<void>? _releaseTask;
  var _iosSessionMayBeActive = false;
  var _closed = false;

  @override
  Future<void> configureSpeechMixing() async {
    _ensureOpen();
    // Audio-session configuration is process-global and another plugin may
    // overwrite it, so restore the local speech policy before every utterance.
    await _audioSessionBackend.configure(_speechMixingConfiguration);
  }

  @override
  Future<void> load(Uint8List wavBytes) async {
    _ensureOpen();
    if (_player != null) {
      throw StateError('The previous generated speech player is still owned.');
    }
    final player = AudioPlayer(handleAudioSessionActivation: false);
    _player = player;
    await player.setAudioSource(_InMemoryWavAudioSource(wavBytes));
  }

  @override
  Future<void> activate() {
    _ensureOpen();
    if (_targetPlatform != TargetPlatform.iOS) return Future.value();
    final existing = _activationTask;
    if (existing != null) return existing;

    late final Future<void> task;
    task = _activateIosSession().whenComplete(() {
      if (identical(_activationTask, task)) _activationTask = null;
    });
    _activationTask = task;
    return task;
  }

  Future<void> _activateIosSession() async {
    // Native activation can succeed after a timeout or lost method-channel
    // reply. Claim tentative ownership before dispatch and retain it until a
    // release that runs after this task has settled performs deactivation.
    _iosSessionMayBeActive = true;
    if (!await _audioSessionBackend.setActive(active: true)) {
      throw StateError('The iOS speech audio session rejected activation.');
    }
  }

  @override
  Future<void> play({required VoidCallback onStarted}) async {
    _ensureOpen();
    final player = _player;
    if (player == null) {
      throw StateError('No generated speech audio is loaded.');
    }

    var started = false;
    final stateSubscription = player.playerStateStream.listen((state) {
      final readyToOutput = switch (state.processingState) {
        ProcessingState.buffering || ProcessingState.ready || ProcessingState.completed => true,
        ProcessingState.idle || ProcessingState.loading => false,
      };
      if (!started && state.playing && readyToOutput) {
        started = true;
        onStarted();
      }
    });

    try {
      await player.play();
      if (player.processingState != ProcessingState.completed) {
        throw StateError('Generated speech playback ended before completion.');
      }
      if (!started) onStarted();
    } finally {
      await stateSubscription.cancel();
    }
  }

  @override
  Future<void> release() {
    final existing = _releaseTask;
    if (existing != null) return existing;

    late final Future<void> task;
    task = _releaseOnce().whenComplete(() {
      if (identical(_releaseTask, task)) _releaseTask = null;
    });
    _releaseTask = task;
    return task;
  }

  Future<void> _releaseOnce() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    final player = _player;
    if (player != null) {
      try {
        await player.dispose();
        if (identical(_player, player)) _player = null;
      } on Object catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }

    final activationTask = _activationTask;
    if (activationTask != null) {
      try {
        await activationTask;
      } on Object {
        // Activation failure belongs to the caller that dispatched it. This
        // barrier only guarantees a possibly late native success is followed
        // by deactivation before release settles.
      }
    }

    if (_targetPlatform == TargetPlatform.iOS && _iosSessionMayBeActive) {
      try {
        await _deactivateIosSession();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
  }

  Future<void> _deactivateIosSession() async {
    for (var attempt = 0; attempt < _iosReleaseAttempts; attempt += 1) {
      final accepted = await _audioSessionBackend.setActive(active: false);
      if (accepted) {
        _iosSessionMayBeActive = false;
        return;
      }
      if (attempt + 1 < _iosReleaseAttempts) {
        // A physical iPhone can retain AVAudioSession briefly after its player
        // stops. The bounded retry preserves ownership until release succeeds.
        await Future<void>.delayed(_iosReleaseRetryDelay);
      }
    }
    throw StateError('The iOS speech audio session rejected deactivation.');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await release();
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The generated speech backend is closed.');
  }
}

// StreamAudioSource is just_audio's only native in-memory byte boundary. It is
// pinned by pubspec and isolated here so an upstream API change stays local.
// ignore: experimental_member_use
final class _InMemoryWavAudioSource extends StreamAudioSource {
  _InMemoryWavAudioSource(this._bytes);

  final Uint8List _bytes;

  @override
  // The response type is part of the same isolated just_audio stream boundary.
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final offset = (start ?? 0).clamp(0, _bytes.length);
    final exclusiveEnd = (end ?? _bytes.length).clamp(offset, _bytes.length);
    // The constructor is required to answer just_audio's byte-range requests.
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: exclusiveEnd - offset,
      offset: offset,
      stream: Stream.value(Uint8List.sublistView(_bytes, offset, exclusiveEnd)),
      contentType: 'audio/wav',
    );
  }
}
