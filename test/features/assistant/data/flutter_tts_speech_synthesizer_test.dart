import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pov_agent/features/assistant/data/adapters/flutter_tts_speech_synthesizer.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeFlutterTts flutterTts;
  FlutterTtsSpeechSynthesizer? synthesizer;

  setUp(() {
    flutterTts = _FakeFlutterTts();
  });

  tearDown(() async {
    await synthesizer?.close();
  });

  FlutterTtsSpeechSynthesizer createSynthesizer({
    String preferredLanguage = 'en-US',
    TargetPlatform targetPlatform = TargetPlatform.android,
    Duration commandTimeout = const Duration(milliseconds: 100),
    Duration utteranceTimeout = const Duration(seconds: 1),
    Duration cancellationDrainTimeout = Duration.zero,
    Duration iosSessionReleaseRetryDelay = Duration.zero,
    int iosSessionReleaseAttempts = 4,
  }) {
    return synthesizer = FlutterTtsSpeechSynthesizer(
      preferredLanguage: preferredLanguage,
      flutterTts: flutterTts,
      targetPlatform: targetPlatform,
      commandTimeout: commandTimeout,
      utteranceTimeout: utteranceTimeout,
      cancellationDrainTimeout: cancellationDrainTimeout,
      iosSessionReleaseRetryDelay: iosSessionReleaseRetryDelay,
      iosSessionReleaseAttempts: iosSessionReleaseAttempts,
    );
  }

  test('selects installed en-US without taking Android audio focus', () async {
    final speech = createSynthesizer().speak('A person entered the room.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'speech command was not dispatched',
    );

    expect(flutterTts.awaitCompletionValues, [false]);
    expect(flutterTts.queueModes, [0]);
    expect(flutterTts.installedLanguageCalls, ['en-US']);
    expect(flutterTts.languageCalls, ['en-US']);
    expect(synthesizer?.resolvedLanguage, 'en-US');
    expect(flutterTts.speechFocusValues, [false]);

    flutterTts
      ..emitStart()
      ..emitCompletion();

    expect(await speech, isA<AppSuccess<void>>());
  });

  test('falls back from unavailable en-US to installed en-GB', () async {
    flutterTts.installedLanguageResults['en-US'] = false;
    final speech = createSynthesizer().speak('A truck is parked nearby.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'fallback language was not selected',
    );

    expect(flutterTts.installedLanguageCalls, ['en-US', 'en-GB']);
    expect(flutterTts.languageCalls, ['en-GB']);
    expect(synthesizer?.resolvedLanguage, 'en-GB');

    flutterTts
      ..emitStart()
      ..emitCompletion();
    expect(await speech, isA<AppSuccess<void>>());
  });

  test('natural iOS completion releases the shared audio session', () async {
    final speech = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
    ).speak('The corridor is quiet.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );

    expect(flutterTts.iosCategory, IosTextToSpeechAudioCategory.playback);
    expect(
      flutterTts.iosCategoryOptions,
      [
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
    );
    expect(flutterTts.iosMode, IosTextToSpeechAudioMode.voicePrompt);
    expect(flutterTts.autoStopValues, [false]);
    expect(flutterTts.sharedSessionValues, [true]);

    flutterTts
      ..emitStart()
      ..emitCompletion();

    expect(await speech, isA<AppSuccess<void>>());
    expect(flutterTts.sharedSessionValues, [true, false]);
  });

  test('retries a transient iOS audio-session release rejection', () async {
    flutterTts.sharedSessionResults.addAll([1, 0, 1]);
    final speech = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
    ).speak('The physical device finishes releasing speech output.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();

    expect(await speech, isA<AppSuccess<void>>());
    expect(flutterTts.sharedSessionValues, [true, false, false]);
  });

  test('terminal callback cancels watchdog while iOS release is pending', () async {
    final release = Completer<dynamic>();
    flutterTts.sharedSessionResults.addAll([1, release.future]);
    final speech = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
      utteranceTimeout: const Duration(milliseconds: 20),
    ).speak('The terminal callback arrived before release settled.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(flutterTts.stopCalls, 0);
    release.complete(1);
    expect(await speech, isA<AppSuccess<void>>());
  });

  test('close joins an in-flight iOS release retry', () async {
    final retryRelease = Completer<dynamic>();
    flutterTts.sharedSessionResults.addAll([1, 0, retryRelease.future]);
    final adapter = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
    );
    final speech = adapter.speak('Close waits for the shared release.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();
    await _waitFor(
      () => flutterTts.sharedSessionValues.length == 3,
      reason: 'iOS release retry did not start',
    );

    final close = adapter.close();
    await _flushEventQueue();
    expect(flutterTts.sharedSessionValues, [true, false, false]);
    expect(flutterTts.startHandlerRegistrations, 1);

    retryRelease.complete(1);
    expect(await speech, isA<AppSuccess<void>>());
    expect(await close, isA<AppSuccess<void>>());
    expect(flutterTts.sharedSessionValues, [true, false, false]);
    expect(flutterTts.startHandlerRegistrations, 2);
  });

  test('bounds repeated iOS audio-session release rejection', () async {
    flutterTts.sharedSessionResults.addAll([1, 0, 0]);
    final speech = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
      iosSessionReleaseAttempts: 2,
    ).speak('The audio session cannot be released.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();

    expect(
      await speech,
      _failureWithCode('system_speech_audio_session_release_failed'),
    );
    expect(flutterTts.sharedSessionValues, [true, false, false]);

    flutterTts.sharedSessionResults.add(1);
  });

  test('does not retry an exceptional iOS audio-session release', () async {
    flutterTts.sharedSessionResults.add(1);
    flutterTts.sharedSessionError = StateError('native channel unavailable');
    final speech = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
    ).speak('The native release command throws.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();

    expect(
      await speech,
      _failureWithCode('system_speech_audio_session_release_failed'),
    );
    expect(flutterTts.sharedSessionValues, [true, false]);

    flutterTts.sharedSessionResults.add(1);
  });

  test('explicit stop bounds the total iOS release attempts', () async {
    flutterTts.sharedSessionResults.addAll([1, 0, 0]);
    final adapter = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
      iosSessionReleaseAttempts: 2,
    );
    final speech = adapter.speak('Stop performs one bounded release operation.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts.emitStart();

    expect(await adapter.stop(), _failureWithCode('system_speech_audio_session_release_failed'));
    expect(await speech, isA<AppSuccess<void>>());
    expect(flutterTts.sharedSessionValues, [true, false, false]);

    flutterTts.sharedSessionResults.add(1);
  });

  test('failed iOS release ownership remains retriable during close', () async {
    flutterTts.sharedSessionResults.addAll([1, 0, 0, 0, 0, 1]);
    final adapter = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
      iosSessionReleaseAttempts: 2,
    );
    final speech = adapter.speak('Release ownership survives rejection.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'iOS speech command was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();

    expect(
      await speech,
      _failureWithCode('system_speech_audio_session_release_failed'),
    );
    expect(
      await adapter.close(),
      _failureWithCode('system_speech_audio_session_release_failed'),
    );
    expect(flutterTts.startHandlerRegistrations, 1);

    expect(await adapter.close(), isA<AppSuccess<void>>());
    expect(flutterTts.sharedSessionValues, [true, false, false, false, false, false]);
    expect(flutterTts.startHandlerRegistrations, 2);
  });

  test('timed-out iOS activation is balanced before failure settles', () async {
    final activation = flutterTts.activationGate = Completer<dynamic>();
    final speech = createSynthesizer(
      targetPlatform: TargetPlatform.iOS,
      commandTimeout: const Duration(milliseconds: 20),
    ).speak('Speech blocked during audio-session activation.');

    expect(
      await speech,
      _failureWithCode('system_speech_audio_session_unavailable'),
    );
    expect(flutterTts.sharedSessionValues, [true, false]);
    expect(flutterTts.spokenTexts, isEmpty);
    activation.complete(1);
  });

  test('rejects a second utterance while speech is active', () async {
    final adapter = createSynthesizer();
    final first = adapter.speak('First observation.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'first utterance was not dispatched',
    );
    final overlapping = await adapter.speak('Stale second observation.');

    expect(overlapping, _failureWithCode('system_speech_busy'));
    expect(flutterTts.spokenTexts, ['First observation.']);

    flutterTts
      ..emitStart()
      ..emitCompletion();
    expect(await first, isA<AppSuccess<void>>());
  });

  test('stop waits for the native cancellation callback before reopening', () async {
    final adapter = createSynthesizer(
      cancellationDrainTimeout: const Duration(seconds: 1),
    );
    final speech = adapter.speak('Speech that will be stopped.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    flutterTts.emitStart();

    var stopSettled = false;
    final stop = adapter.stop();
    unawaited(
      stop.then<void>((_) {
        stopSettled = true;
      }),
    );
    await _flushEventQueue();

    expect(await speech, isA<AppSuccess<void>>());
    expect(flutterTts.stopCalls, 1);
    expect(stopSettled, isFalse);

    flutterTts.emitCancellation();

    expect(await stop, isA<AppSuccess<void>>());
    expect(stopSettled, isTrue);
  });

  test('native cancellation recovers a rejected stop command', () async {
    flutterTts.stopResult = 0;
    final adapter = createSynthesizer(
      cancellationDrainTimeout: const Duration(seconds: 1),
    );
    final speech = adapter.speak('Speech stopped despite a lost reply.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    flutterTts.emitStart();
    final stop = adapter.stop();
    flutterTts.emitCancellation();

    expect(await speech, isA<AppSuccess<void>>());
    expect(await stop, isA<AppSuccess<void>>());

    flutterTts.stopResult = 1;
    final replay = adapter.speak('Replay after recovered stop.');
    await _waitFor(
      () => flutterTts.spokenTexts.length == 2,
      reason: 'replay remained blocked after native cancellation',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();
    expect(await replay, isA<AppSuccess<void>>());
  });

  test('ignores a stopped utterance callback before replay starts', () async {
    final adapter = createSynthesizer(
      cancellationDrainTimeout: const Duration(seconds: 1),
    );
    final first = adapter.speak('Original observation.');

    await _waitFor(
      () => flutterTts.spokenTexts.length == 1,
      reason: 'original utterance was not dispatched',
    );
    flutterTts.emitStart();
    final stop = adapter.stop();
    flutterTts.emitCancellation();
    expect(await stop, isA<AppSuccess<void>>());
    expect(await first, isA<AppSuccess<void>>());

    final replay = adapter.speak('Original observation.');
    await _waitFor(
      () => flutterTts.spokenTexts.length == 2,
      reason: 'replay was not dispatched',
    );

    var replaySettled = false;
    unawaited(
      replay.then<void>((_) {
        replaySettled = true;
      }),
    );

    // A terminal callback cannot belong to the replay until its start callback.
    flutterTts.emitCompletion();
    await _flushEventQueue();
    expect(replaySettled, isFalse);

    flutterTts
      ..emitStart()
      ..emitCompletion();
    expect(await replay, isA<AppSuccess<void>>());
  });

  test('normalizes a native speech error', () async {
    final speech = createSynthesizer().speak('An utterance that fails.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitError(StateError('engine failed'));

    expect(await speech, _failureWithCode('system_speech_native_error'));
    await _waitFor(
      () => flutterTts.stopCalls == 1,
      reason: 'native error did not quiesce the engine',
    );
  });

  test('native failure settles only after the recovery stop barrier', () async {
    final stopGate = flutterTts.stopGate = Completer<dynamic>();
    final speech = createSynthesizer().speak('A failing active utterance.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    var speechSettled = false;
    unawaited(
      speech.then<void>((_) {
        speechSettled = true;
      }),
    );
    flutterTts
      ..emitStart()
      ..emitError(StateError('engine failed'));
    await _flushEventQueue();

    expect(flutterTts.stopCalls, 1);
    expect(speechSettled, isFalse);

    stopGate.complete(1);
    expect(await speech, _failureWithCode('system_speech_native_error'));
    expect(speechSettled, isTrue);
  });

  test('stops rather than retaining a natively paused utterance', () async {
    final speech = createSynthesizer().speak('An utterance that pauses.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    flutterTts
      ..emitStart()
      ..emitPause();

    expect(await speech, _failureWithCode('system_speech_paused'));
    await _waitFor(
      () => flutterTts.stopCalls == 1,
      reason: 'paused utterance was not discarded',
    );
  });

  test('bounds a native speak command that never replies', () async {
    final command = flutterTts.speakGate = Completer<dynamic>();
    final adapter = createSynthesizer(
      commandTimeout: const Duration(milliseconds: 20),
    );
    final speech = adapter.speak('A command that never returns.');

    expect(await speech, _failureWithCode('system_speech_start_failed'));
    expect(flutterTts.stopCalls, 1);

    flutterTts.speakGate = null;
    final replay = adapter.speak('Speech after command recovery.');
    await _waitFor(
      () => flutterTts.spokenTexts.length == 2,
      reason: 'replay remained blocked after command recovery',
    );
    flutterTts
      ..emitStart()
      ..emitCompletion();
    expect(await replay, isA<AppSuccess<void>>());
    command.complete(1);
  });

  test('watchdog stops an utterance with no terminal callback', () async {
    final speech = createSynthesizer(
      utteranceTimeout: const Duration(milliseconds: 20),
    ).speak('An utterance without a completion callback.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    flutterTts.emitStart();

    expect(await speech, _failureWithCode('system_speech_timeout'));
    expect(flutterTts.stopCalls, 1);
  });

  test('concurrent and repeated close calls share one teardown', () async {
    final adapter = createSynthesizer(
      cancellationDrainTimeout: const Duration(seconds: 1),
    );
    final speech = adapter.speak('Speech active during close.');

    await _waitFor(
      () => flutterTts.spokenTexts.isNotEmpty,
      reason: 'utterance was not dispatched',
    );
    flutterTts.emitStart();

    final firstClose = adapter.close();
    final concurrentClose = adapter.close();
    expect(identical(firstClose, concurrentClose), isTrue);
    expect(flutterTts.stopCalls, 1);

    flutterTts.emitCancellation();
    expect(await speech, isA<AppSuccess<void>>());
    expect(await firstClose, isA<AppSuccess<void>>());

    final repeatedClose = adapter.close();
    expect(identical(firstClose, repeatedClose), isTrue);
    expect(await repeatedClose, isA<AppSuccess<void>>());
    expect(flutterTts.stopCalls, 1);
    expect(flutterTts.startHandlerRegistrations, 2);
    expect(
      await adapter.speak('Speech after close.'),
      _failureWithCode('system_speech_closed'),
    );
  });

  test('close joins an in-flight iOS activation before releasing handlers', () async {
    final activation = flutterTts.activationGate = Completer<dynamic>();
    final adapter = createSynthesizer(targetPlatform: TargetPlatform.iOS);
    final speech = adapter.speak('Speech stopped during activation.');

    await _waitFor(
      () => flutterTts.sharedSessionValues.length == 1,
      reason: 'audio-session activation was not requested',
    );

    var closeSettled = false;
    final close = adapter.close();
    unawaited(
      close.then<void>((_) {
        closeSettled = true;
      }),
    );
    await _flushEventQueue();

    expect(await speech, isA<AppSuccess<void>>());
    expect(closeSettled, isFalse);
    expect(flutterTts.startHandlerRegistrations, 1);

    activation.complete(1);

    expect(await close, isA<AppSuccess<void>>());
    expect(flutterTts.sharedSessionValues, [true, false]);
    expect(flutterTts.spokenTexts, isEmpty);
    expect(flutterTts.startHandlerRegistrations, 2);
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

final class _FakeFlutterTts extends FlutterTts {
  final Map<String, Object?> languageResults = <String, Object?>{};
  final Map<String, Object?> installedLanguageResults = <String, Object?>{};
  final List<bool> awaitCompletionValues = <bool>[];
  final List<int> queueModes = <int>[];
  final List<String> languageCalls = <String>[];
  final List<String> installedLanguageCalls = <String>[];
  final List<String> spokenTexts = <String>[];
  final List<bool> speechFocusValues = <bool>[];
  final List<bool> sharedSessionValues = <bool>[];
  final List<Object?> sharedSessionResults = <Object?>[];
  final List<bool> autoStopValues = <bool>[];

  IosTextToSpeechAudioCategory? iosCategory;
  List<IosTextToSpeechAudioCategoryOptions>? iosCategoryOptions;
  IosTextToSpeechAudioMode? iosMode;
  Completer<dynamic>? activationGate;
  Completer<dynamic>? speakGate;
  Completer<dynamic>? stopGate;
  Object? speakError;
  Object? speakResult = 1;
  Object? stopResult = 1;
  Object? sharedSessionError;
  int stopCalls = 0;
  int startHandlerRegistrations = 0;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) {
    awaitCompletionValues.add(awaitCompletion);
    return Future<dynamic>.value(1);
  }

  @override
  Future<dynamic> setQueueMode(int queueMode) {
    queueModes.add(queueMode);
    return Future<dynamic>.value(1);
  }

  @override
  Future<dynamic> setLanguage(String language) {
    languageCalls.add(language);
    return Future<dynamic>.value(languageResults[language] ?? 1);
  }

  @override
  Future<dynamic> isLanguageInstalled(String language) {
    installedLanguageCalls.add(language);
    return Future<dynamic>.value(installedLanguageResults[language] ?? true);
  }

  @override
  Future<dynamic> setIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options, [
    IosTextToSpeechAudioMode mode = IosTextToSpeechAudioMode.defaultMode,
  ]) {
    iosCategory = category;
    iosCategoryOptions = List<IosTextToSpeechAudioCategoryOptions>.of(options);
    iosMode = mode;
    return Future<dynamic>.value(1);
  }

  @override
  Future<dynamic> autoStopSharedSession(bool autoStop) {
    autoStopValues.add(autoStop);
    return Future<dynamic>.value(1);
  }

  @override
  Future<dynamic> setSharedInstance(bool sharedSession) {
    sharedSessionValues.add(sharedSession);
    if (sharedSession && activationGate != null) {
      return activationGate!.future;
    }
    if (!sharedSession && sharedSessionError != null) {
      final error = sharedSessionError;
      sharedSessionError = null;
      return Future<dynamic>.error(error!);
    }
    final result = sharedSessionResults.isEmpty ? 1 : sharedSessionResults.removeAt(0);
    return result is Future<dynamic> ? result : Future<dynamic>.value(result);
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spokenTexts.add(text);
    speechFocusValues.add(focus);
    final error = speakError;
    if (error != null) return Future<dynamic>.error(error);
    return speakGate?.future ?? Future<dynamic>.value(speakResult);
  }

  @override
  Future<dynamic> stop() {
    stopCalls += 1;
    return stopGate?.future ?? Future<dynamic>.value(stopResult);
  }

  @override
  void setStartHandler(VoidCallback callback) {
    startHandlerRegistrations += 1;
    startHandler = callback;
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    completionHandler = callback;
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    cancelHandler = callback;
  }

  @override
  void setPauseHandler(VoidCallback callback) {
    pauseHandler = callback;
  }

  @override
  void setErrorHandler(ErrorHandler handler) {
    errorHandler = handler;
  }

  void emitStart() => startHandler?.call();

  void emitCompletion() => completionHandler?.call();

  void emitCancellation() => cancelHandler?.call();

  void emitPause() => pauseHandler?.call();

  void emitError(Object error) => errorHandler?.call(error);
}
