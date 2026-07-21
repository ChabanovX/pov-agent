import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/piper_runtime_configuration.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/data/adapters/generated_speech_audio_player.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/ffi/piper_speech_generator.dart';
import 'package:pov_agent/features/assistant/data/models/generated_speech_audio.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  group('PiperSpeechSynthesizer', () {
    late _FakePiperModelStore modelStore;
    late _FakePiperSpeechGenerator generator;
    late _FakeGeneratedSpeechAudioPlayer audioPlayer;
    late PiperSpeechSynthesizer synthesizer;

    setUp(() {
      modelStore = _FakePiperModelStore();
      generator = _FakePiperSpeechGenerator();
      audioPlayer = _FakeGeneratedSpeechAudioPlayer();
      synthesizer = PiperSpeechSynthesizer(
        modelStore: modelStore,
        generator: generator,
        audioPlayer: audioPlayer,
        configuration: _configuration,
      );
    });

    test('frees generation before playback and records diagnostics', () async {
      final events = <String>[];
      generator.events = events;
      audioPlayer
        ..events = events
        ..onPlay = (_) async {
          expect(synthesizer.nativeRuntimeActive, isFalse);
          expect(
            synthesizer.lastNativeRuntimeCreatedAtUtc,
            _runtimeCreatedAtUtc,
          );
          expect(synthesizer.lastNativeRuntimeFreedAtUtc, _runtimeFreedAtUtc);
          return const AppSuccess<void>(null);
        };

      expect(
        await synthesizer.speak('  A person entered the room.  '),
        isA<AppSuccess<void>>(),
      );

      expect(events, ['generator:start', 'generator:settle', 'player:play']);
      expect(modelStore.prepareCalls, 1);
      expect(generator.texts, ['A person entered the room.']);
      expect(generator.bundles, [_bundle]);
      expect(generator.configurations, [_configuration]);
      expect(audioPlayer.playedAudio, hasLength(1));
      expect(synthesizer.nativeRuntimeActive, isFalse);
      expect(synthesizer.synthesisAttempts, 1);
      expect(synthesizer.synthesisSettlements, 1);
      expect(synthesizer.completedPlaybacks, 1);
      expect(synthesizer.lastSampleCount, 3);
      expect(synthesizer.lastSampleRateHz, 22050);
      expect(synthesizer.lastPeakAmplitude, closeTo(0.75, 0.000001));
      expect(
        synthesizer.lastNativeRuntimeCreatedAtUtc,
        _runtimeCreatedAtUtc,
      );
      expect(synthesizer.lastNativeRuntimeFreedAtUtc, _runtimeFreedAtUtc);
      expect(identical(synthesizer.modelStore, modelStore), isTrue);
    });

    test(
      'reports active only after construction and until native free returns',
      () async {
        final construction = Completer<void>();
        final generation = Completer<GeneratedSpeechAudio>();
        generator
          ..onBeforeRuntimeCreated = () {
            return construction.future;
          }
          ..onGenerate = (_, _, _) => generation.future;

        final speech = synthesizer.speak('Observe the native lifecycle.');
        await _waitFor(
          () => generator.texts.isNotEmpty,
          reason: 'generator was not entered',
        );

        expect(synthesizer.nativeRuntimeActive, isFalse);
        expect(synthesizer.lastNativeRuntimeCreatedAtUtc, isNull);
        expect(synthesizer.lastNativeRuntimeFreedAtUtc, isNull);

        construction.complete();
        await _waitFor(
          () => synthesizer.nativeRuntimeActive,
          reason: 'runtime creation was not observed',
        );

        expect(
          synthesizer.lastNativeRuntimeCreatedAtUtc,
          _runtimeCreatedAtUtc,
        );
        expect(synthesizer.lastNativeRuntimeFreedAtUtc, isNull);

        generation.complete(_validAudio());

        expect(await speech, isA<AppSuccess<void>>());
        expect(synthesizer.nativeRuntimeActive, isFalse);
        expect(synthesizer.lastNativeRuntimeFreedAtUtc, _runtimeFreedAtUtc);
      },
    );

    final invalidAudioCases = <String, GeneratedSpeechAudio>{
      'empty PCM': GeneratedSpeechAudio(samples: const [], sampleRateHz: 22050),
      'invalid sample rate': GeneratedSpeechAudio(
        samples: const [0.5],
        sampleRateHz: 0,
      ),
      'non-finite PCM': GeneratedSpeechAudio(
        samples: const [double.nan],
        sampleRateHz: 22050,
      ),
      'infinite PCM': GeneratedSpeechAudio(
        samples: const [double.infinity],
        sampleRateHz: 22050,
      ),
      'silent PCM': GeneratedSpeechAudio(
        samples: const [0, -0.0, 0],
        sampleRateHz: 22050,
      ),
    };
    for (final MapEntry(key: description, value: invalidAudio) in invalidAudioCases.entries) {
      test('rejects $description before playback', () async {
        generator.onGenerate = (_, _, _) async => invalidAudio;

        expect(
          await synthesizer.speak('Invalid generated audio.'),
          _failureWithCode('piper_synthesis_invalid_audio'),
        );
        expect(audioPlayer.playedAudio, isEmpty);
        expect(synthesizer.nativeRuntimeActive, isFalse);
        expect(synthesizer.synthesisAttempts, 1);
        expect(synthesizer.synthesisSettlements, 1);
        expect(synthesizer.completedPlaybacks, 0);
      });
    }

    test('propagates model preparation failure without generation', () async {
      modelStore.onPrepare = () async => const AppError(
        NetworkFailure(code: 'piper_model_download_failed'),
      );

      expect(
        await synthesizer.speak('Model preparation fails.'),
        _failureWithCode('piper_model_download_failed'),
      );
      expect(generator.texts, isEmpty);
      expect(audioPlayer.playedAudio, isEmpty);
      expect(synthesizer.synthesisAttempts, 0);
      expect(synthesizer.synthesisSettlements, 0);
    });

    test('normalizes generator exceptions after runtime settlement', () async {
      generator.onGenerate = (_, _, _) async {
        throw StateError('native synthesis failed');
      };

      expect(
        await synthesizer.speak('Generator failure.'),
        _failureWithCode('piper_synthesis_failed'),
      );
      expect(audioPlayer.playedAudio, isEmpty);
      expect(synthesizer.nativeRuntimeActive, isFalse);
      expect(synthesizer.synthesisAttempts, 1);
      expect(synthesizer.synthesisSettlements, 1);
    });

    test('rejects overlap, then permits replay after playback', () async {
      final firstGeneration = Completer<GeneratedSpeechAudio>();
      var generationCall = 0;
      generator.onGenerate = (_, _, _) {
        generationCall += 1;
        if (generationCall == 1) return firstGeneration.future;
        return Future<GeneratedSpeechAudio>.value(_validAudio());
      };

      final first = synthesizer.speak('First local utterance.');
      await _waitFor(
        () => generator.texts.isNotEmpty,
        reason: 'first generation did not start',
      );

      expect(
        await synthesizer.speak('Overlapping local utterance.'),
        _failureWithCode('piper_speech_busy'),
      );

      firstGeneration.complete(_validAudio());
      expect(await first, isA<AppSuccess<void>>());
      expect(
        await synthesizer.speak('Replay after playback.'),
        isA<AppSuccess<void>>(),
      );
      expect(generator.texts, [
        'First local utterance.',
        'Replay after playback.',
      ]);
      expect(synthesizer.synthesisAttempts, 2);
      expect(synthesizer.synthesisSettlements, 2);
      expect(synthesizer.completedPlaybacks, 2);
    });

    test('stop during generation waits for native settlement', () async {
      final generation = Completer<GeneratedSpeechAudio>();
      generator.onGenerate = (_, _, _) => generation.future;

      final speech = synthesizer.speak('Generation that will be stopped.');
      await _waitFor(
        () => generator.texts.isNotEmpty,
        reason: 'generation did not start',
      );
      expect(synthesizer.nativeRuntimeActive, isTrue);

      var stopSettled = false;
      final stop = synthesizer.stop();
      unawaited(stop.then<void>((_) => stopSettled = true));
      await _flushEventQueue();

      expect(modelStore.suspendCalls, 1);
      expect(audioPlayer.stopCalls, 1);
      expect(stopSettled, isFalse);
      expect(
        await synthesizer.speak('Blocked until stop settles.'),
        _failureWithCode('piper_speech_busy'),
      );

      generation.complete(_validAudio());

      expect(await speech, isA<AppSuccess<void>>());
      expect(await stop, isA<AppSuccess<void>>());
      expect(stopSettled, isTrue);
      expect(audioPlayer.playedAudio, isEmpty);
      expect(synthesizer.nativeRuntimeActive, isFalse);
      expect(synthesizer.synthesisAttempts, 1);
      expect(synthesizer.synthesisSettlements, 1);
      expect(synthesizer.completedPlaybacks, 0);
    });

    test('stop during playback prevents a cancelled completion count', () async {
      final playback = Completer<AppResult<void>>();
      audioPlayer
        ..onPlay = ((_) => playback.future)
        ..onStop = () async {
          if (!playback.isCompleted) {
            playback.complete(
              const AppError(
                DeviceUnavailableFailure(code: 'local_speech_playback_failed'),
              ),
            );
          }
          return const AppSuccess<void>(null);
        };

      final speech = synthesizer.speak('Playback that will be stopped.');
      await _waitFor(
        () => audioPlayer.playedAudio.isNotEmpty,
        reason: 'playback did not start',
      );

      expect(await synthesizer.stop(), isA<AppSuccess<void>>());
      expect(await speech, isA<AppSuccess<void>>());
      expect(audioPlayer.stopCalls, 1);
      expect(modelStore.suspendCalls, 1);
      expect(synthesizer.completedPlaybacks, 0);
      expect(synthesizer.synthesisAttempts, 1);
      expect(synthesizer.synthesisSettlements, 1);
    });

    test('propagates terminal playback failure without rewriting it', () async {
      audioPlayer.onPlay = (_) async => const AppError(
        DeviceUnavailableFailure(code: 'local_speech_playback_failed'),
      );

      expect(
        await synthesizer.speak('Playback fails after start.'),
        _failureWithCode('local_speech_playback_failed'),
      );
      expect(synthesizer.completedPlaybacks, 0);
      expect(
        isPiperFallbackEligible(
          const DeviceUnavailableFailure(
            code: 'local_speech_playback_failed',
          ),
        ),
        isFalse,
      );
    });

    test('close invalidates generation and waits for native settlement', () async {
      final generation = Completer<GeneratedSpeechAudio>();
      generator.onGenerate = (_, _, _) => generation.future;

      final speech = synthesizer.speak('Generation interrupted by close.');
      await _waitFor(
        () => generator.texts.isNotEmpty,
        reason: 'generation did not start',
      );

      var closeSettled = false;
      final close = synthesizer.close();
      unawaited(close.then<void>((_) => closeSettled = true));
      await _flushEventQueue();

      expect(modelStore.closeCalls, 1);
      expect(audioPlayer.closeCalls, 1);
      expect(closeSettled, isFalse);

      generation.complete(_validAudio());

      expect(await speech, isA<AppSuccess<void>>());
      expect(await close, isA<AppSuccess<void>>());
      expect(audioPlayer.playedAudio, isEmpty);
      expect(synthesizer.nativeRuntimeActive, isFalse);
      expect(
        await synthesizer.speak('Speech after close.'),
        _failureWithCode('piper_speech_closed'),
      );
    });

    test('failed close remains retriable for both owned resources', () async {
      var playerCloseAttempt = 0;
      audioPlayer.onClose = () async {
        playerCloseAttempt += 1;
        if (playerCloseAttempt == 1) {
          return const AppError(
            DeviceUnavailableFailure(code: 'local_player_close_failed'),
          );
        }
        return const AppSuccess<void>(null);
      };

      expect(
        await synthesizer.close(),
        _failureWithCode('local_player_close_failed'),
      );
      expect(await synthesizer.close(), isA<AppSuccess<void>>());
      expect(audioPlayer.closeCalls, 2);
      expect(modelStore.closeCalls, 2);
    });
  });
}

const _bundle = VerifiedPiperModelBundle(
  modelId: 'vits-piper-en_US-ljspeech-medium-int8',
  revision: 'tts-models',
  bundleDirectoryPath: '/models/piper',
  modelFilePath: '/models/piper/en_US-ljspeech-medium.onnx',
  tokensFilePath: '/models/piper/tokens.txt',
  espeakDataDirectoryPath: '/models/piper/espeak-ng-data',
  extractedByteSize: 37347875,
  extractedFileCount: 359,
  bundleTreeSha256: 'verified-tree-sha256',
);

const _configuration = PiperRuntimeConfiguration(
  provider: 'cpu',
  threadCount: 1,
  speakerId: 0,
  noiseScale: 0.667,
  noiseScaleW: 0.8,
  lengthScale: 1,
  speed: 1,
  silenceScale: 0.2,
  maxSentences: 1,
  debug: false,
);

final _runtimeCreatedAtUtc = DateTime.utc(2026, 7, 21, 10);
final _runtimeFreedAtUtc = DateTime.utc(2026, 7, 21, 10, 0, 1);

GeneratedSpeechAudio _validAudio() {
  return GeneratedSpeechAudio(
    samples: const [0.25, -0.75, 0.5],
    sampleRateHz: 22050,
  );
}

Matcher _failureWithCode(String code) {
  return isA<AppError<void>>().having(
    (result) => result.failure.code,
    'failure code',
    code,
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  required String reason,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail(reason);
}

Future<void> _flushEventQueue() async {
  for (var iteration = 0; iteration < 3; iteration += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakePiperModelStore implements ModelStore<VerifiedPiperModelBundle> {
  ModelStoreState<VerifiedPiperModelBundle> _current = const ModelStoreState<VerifiedPiperModelBundle>.idle();

  Future<AppResult<VerifiedPiperModelBundle>> Function()? onPrepare;
  Future<void> Function()? onSuspend;
  Future<void> Function()? onClose;
  int prepareCalls = 0;
  int suspendCalls = 0;
  int closeCalls = 0;

  @override
  ModelStoreState<VerifiedPiperModelBundle> get current => _current;

  @override
  Stream<ModelStoreState<VerifiedPiperModelBundle>> get states =>
      const Stream<ModelStoreState<VerifiedPiperModelBundle>>.empty();

  @override
  Future<AppResult<VerifiedPiperModelBundle>> prepare() async {
    prepareCalls += 1;
    final callback = onPrepare;
    final result = callback == null ? const AppSuccess<VerifiedPiperModelBundle>(_bundle) : await callback();
    if (result case AppSuccess<VerifiedPiperModelBundle>(:final value)) {
      _current = ModelStoreState<VerifiedPiperModelBundle>.ready(value);
    }
    return result;
  }

  @override
  Future<void> suspend() async {
    suspendCalls += 1;
    await onSuspend?.call();
    _current = const ModelStoreState<VerifiedPiperModelBundle>.suspended();
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await onClose?.call();
  }
}

final class _FakePiperSpeechGenerator implements PiperSpeechGenerator {
  final List<String> texts = <String>[];
  final List<VerifiedPiperModelBundle> bundles = <VerifiedPiperModelBundle>[];
  final List<PiperRuntimeConfiguration> configurations = <PiperRuntimeConfiguration>[];

  Future<GeneratedSpeechAudio> Function(
    String text,
    VerifiedPiperModelBundle bundle,
    PiperRuntimeConfiguration configuration,
  )?
  onGenerate;
  Future<void> Function()? onBeforeRuntimeCreated;
  List<String>? events;

  @override
  Future<PiperSpeechGeneration> generate({
    required String text,
    required VerifiedPiperModelBundle bundle,
    required PiperRuntimeConfiguration configuration,
    required void Function(DateTime createdAtUtc) onRuntimeCreated,
    required void Function(DateTime freedAtUtc) onRuntimeFreed,
  }) async {
    texts.add(text);
    bundles.add(bundle);
    configurations.add(configuration);
    events?.add('generator:start');
    await onBeforeRuntimeCreated?.call();
    onRuntimeCreated(_runtimeCreatedAtUtc);
    late final GeneratedSpeechAudio audio;
    try {
      final callback = onGenerate;
      audio = callback == null ? _validAudio() : await callback(text, bundle, configuration);
    } finally {
      onRuntimeFreed(_runtimeFreedAtUtc);
      events?.add('generator:settle');
    }
    return PiperSpeechGeneration(
      audio: audio,
      runtimeCreatedAtUtc: _runtimeCreatedAtUtc,
      runtimeFreedAtUtc: _runtimeFreedAtUtc,
    );
  }
}

final class _FakeGeneratedSpeechAudioPlayer implements GeneratedSpeechAudioPlayer {
  final List<GeneratedSpeechAudio> playedAudio = <GeneratedSpeechAudio>[];

  Future<AppResult<void>> Function(GeneratedSpeechAudio audio)? onPlay;
  Future<AppResult<void>> Function()? onStop;
  Future<AppResult<void>> Function()? onClose;
  List<String>? events;
  int stopCalls = 0;
  int closeCalls = 0;

  @override
  Future<AppResult<void>> play(GeneratedSpeechAudio audio) async {
    playedAudio.add(audio);
    events?.add('player:play');
    return await onPlay?.call(audio) ?? const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls += 1;
    return await onStop?.call() ?? const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> close() async {
    closeCalls += 1;
    return await onClose?.call() ?? const AppSuccess<void>(null);
  }
}
