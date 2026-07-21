import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/fallback_speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/data/adapters/piper_speech_synthesizer.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  group('FallbackSpeechSynthesizer', () {
    late _ControlledSpeechSynthesizer primary;
    late _ControlledSpeechSynthesizer fallback;
    late FallbackSpeechSynthesizer synthesizer;

    setUp(() {
      primary = _ControlledSpeechSynthesizer();
      fallback = _ControlledSpeechSynthesizer();
      synthesizer = FallbackSpeechSynthesizer(
        primary: primary,
        fallback: fallback,
        shouldFallback: isPiperFallbackEligible,
      );
    });

    test('returns primary success without touching fallback', () async {
      expect(
        await synthesizer.speak('A person entered the room.'),
        isA<AppSuccess<void>>(),
      );

      expect(primary.spokenTexts, ['A person entered the room.']);
      expect(fallback.spokenTexts, isEmpty);
    });

    test('uses fallback for an eligible failure before playback', () async {
      primary.enqueueSpeak(
        () async => const AppError(
          DeviceUnavailableFailure(
            code: 'local_speech_playback_start_failed',
          ),
        ),
      );

      expect(
        await synthesizer.speak('A bicycle is near the door.'),
        isA<AppSuccess<void>>(),
      );

      expect(primary.spokenTexts, ['A bicycle is near the door.']);
      expect(fallback.spokenTexts, ['A bicycle is near the door.']);
    });

    test('does not repeat speech after playback has started', () async {
      primary.enqueueSpeak(
        () async => const AppError(
          DeviceUnavailableFailure(code: 'local_speech_playback_failed'),
        ),
      );

      expect(
        await synthesizer.speak('This utterance already became audible.'),
        _failureWithCode('local_speech_playback_failed'),
      );
      expect(fallback.spokenTexts, isEmpty);
    });

    test('keeps unknown and cleanup failures fail-closed', () async {
      for (final code in [
        'local_speech_playback_cleanup_failed',
        'piper_speech_unexpected',
        'future_piper_failure',
      ]) {
        primary.enqueueSpeak(
          () async => AppError(
            DeviceUnavailableFailure(code: code),
          ),
        );

        expect(
          await synthesizer.speak('Do not repeat an uncertain utterance.'),
          _failureWithCode(code),
        );
      }

      expect(fallback.spokenTexts, isEmpty);
    });

    test('stop invalidates a late primary failure before fallback', () async {
      final primaryResult = Completer<AppResult<void>>();
      primary.enqueueSpeak(() => primaryResult.future);

      final speech = synthesizer.speak('Speech that will be stopped.');
      await _waitFor(
        () => primary.spokenTexts.isNotEmpty,
        reason: 'primary speech did not start',
      );

      var stopSettled = false;
      final stop = synthesizer.stop();
      unawaited(stop.then<void>((_) => stopSettled = true));
      await _flushEventQueue();

      expect(primary.stopCalls, 1);
      expect(fallback.stopCalls, 1);
      expect(stopSettled, isFalse);

      primaryResult.complete(
        const AppError(
          DeviceUnavailableFailure(
            code: 'local_speech_playback_start_failed',
          ),
        ),
      );

      expect(await speech, isA<AppSuccess<void>>());
      expect(await stop, isA<AppSuccess<void>>());
      expect(fallback.spokenTexts, isEmpty);
    });

    test('rejects overlap, then permits replay after settlement', () async {
      final firstResult = Completer<AppResult<void>>();
      primary.enqueueSpeak(() => firstResult.future);

      final first = synthesizer.speak('First observation.');
      await _waitFor(
        () => primary.spokenTexts.isNotEmpty,
        reason: 'first primary utterance did not start',
      );

      expect(
        await synthesizer.speak('Overlapping observation.'),
        _failureWithCode('speech_coordinator_busy'),
      );

      firstResult.complete(const AppSuccess<void>(null));
      expect(await first, isA<AppSuccess<void>>());
      expect(
        await synthesizer.speak('Replay after settlement.'),
        isA<AppSuccess<void>>(),
      );
      expect(primary.spokenTexts, [
        'First observation.',
        'Replay after settlement.',
      ]);
    });

    test('close cancels active fallback decision and waits for it', () async {
      final primaryResult = Completer<AppResult<void>>();
      primary.enqueueSpeak(() => primaryResult.future);

      final speech = synthesizer.speak('Close during primary speech.');
      await _waitFor(
        () => primary.spokenTexts.isNotEmpty,
        reason: 'primary speech did not start',
      );

      var closeSettled = false;
      final close = synthesizer.close();
      unawaited(close.then<void>((_) => closeSettled = true));
      await _flushEventQueue();

      expect(primary.closeCalls, 1);
      expect(fallback.closeCalls, 1);
      expect(closeSettled, isFalse);

      primaryResult.complete(
        const AppError(
          DeviceUnavailableFailure(
            code: 'local_speech_playback_start_failed',
          ),
        ),
      );

      expect(await speech, isA<AppSuccess<void>>());
      expect(await close, isA<AppSuccess<void>>());
      expect(fallback.spokenTexts, isEmpty);
      expect(
        await synthesizer.speak('Speech after close.'),
        _failureWithCode('speech_coordinator_closed'),
      );
    });

    test('failed close remains retriable for both owned backends', () async {
      primary
        ..enqueueClose(
          () async => const AppError(
            DeviceUnavailableFailure(code: 'primary_close_failed'),
          ),
        )
        ..enqueueClose(() async => const AppSuccess<void>(null));
      fallback
        ..enqueueClose(() async => const AppSuccess<void>(null))
        ..enqueueClose(() async => const AppSuccess<void>(null));

      expect(
        await synthesizer.close(),
        _failureWithCode('primary_close_failed'),
      );
      expect(await synthesizer.close(), isA<AppSuccess<void>>());
      expect(primary.closeCalls, 2);
      expect(fallback.closeCalls, 2);
    });
  });
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

final class _ControlledSpeechSynthesizer implements SpeechSynthesizer {
  final List<String> spokenTexts = <String>[];
  final List<Future<AppResult<void>> Function()> _speakResults = <Future<AppResult<void>> Function()>[];
  final List<Future<AppResult<void>> Function()> _closeResults = <Future<AppResult<void>> Function()>[];

  int stopCalls = 0;
  int closeCalls = 0;

  void enqueueSpeak(Future<AppResult<void>> Function() result) {
    _speakResults.add(result);
  }

  void enqueueClose(Future<AppResult<void>> Function() result) {
    _closeResults.add(result);
  }

  @override
  Future<AppResult<void>> speak(String text) {
    spokenTexts.add(text);
    if (_speakResults.isEmpty) {
      return Future<AppResult<void>>.value(const AppSuccess<void>(null));
    }
    return _speakResults.removeAt(0)();
  }

  @override
  Future<AppResult<void>> stop() async {
    stopCalls += 1;
    return const AppSuccess<void>(null);
  }

  @override
  Future<AppResult<void>> close() {
    closeCalls += 1;
    if (_closeResults.isEmpty) {
      return Future<AppResult<void>>.value(const AppSuccess<void>(null));
    }
    return _closeResults.removeAt(0)();
  }
}
