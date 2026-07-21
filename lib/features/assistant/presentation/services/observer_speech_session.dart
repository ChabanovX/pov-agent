import 'dart:async';

import 'package:pov_agent/features/assistant/application/ports/speech_synthesizer.dart';
import 'package:pov_agent/features/assistant/presentation/services/observer_speech_target.dart';
import 'package:pov_agent/shared/domain/app_failure.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Metadata retained while one committed transcript entry is being spoken.
final class ObserverActiveSpeech {
  /// Creates a tagged utterance for [target].
  const ObserverActiveSpeech({
    required this.runId,
    required this.target,
  });

  /// Monotonic identifier used to reject stale terminal callbacks.
  final int runId;

  /// Committed comment or hands-free answer being spoken.
  final ObserverSpeechTarget target;

  /// Comment index when [target] is an automatic comment.
  int? get commentIndex => switch (target) {
    ObserverCommentSpeechTarget(:final commentIndex) => commentIndex,
    ObserverMessageSpeechTarget() => null,
    ObserverVoiceAnswerSpeechTarget() => null,
  };

  /// Message index when [target] is a completed Assistant dialogue response.
  int? get messageIndex => switch (target) {
    ObserverCommentSpeechTarget() => null,
    ObserverMessageSpeechTarget(:final messageIndex) => messageIndex,
    ObserverVoiceAnswerSpeechTarget() => null,
  };

  /// Voice turn when [target] is a hands-free answer.
  int? get voiceTurnId => switch (target) {
    ObserverCommentSpeechTarget() => null,
    ObserverMessageSpeechTarget() => null,
    ObserverVoiceAnswerSpeechTarget(:final turnId) => turnId,
  };
}

/// A terminal speech result tagged with the utterance that produced it.
final class ObserverSpeechCompleted {
  /// Creates a tagged terminal speech update.
  const ObserverSpeechCompleted({
    required this.speech,
    required this.result,
  });

  /// The utterance that settled.
  final ObserverActiveSpeech speech;

  /// Normal completion or a recoverable native speech failure.
  final AppResult<void> result;
}

/// Owns the observer's one-at-a-time speech task and stale-result policy.
///
/// Active metadata remains occupied until the Bloc consumes completion. This
/// closes the interval where native speech has ended but its queued projection
/// has not, so a timer tick cannot overtake the speech terminal event. The
/// injected [SpeechSynthesizer] remains process-owned and is not closed here.
final class ObserverSpeechSession {
  /// Creates an idle speech session that forwards tagged terminal updates.
  factory ObserverSpeechSession({
    required SpeechSynthesizer speechSynthesizer,
    required void Function(ObserverSpeechCompleted update) onUpdate,
  }) {
    return ObserverSpeechSession._(speechSynthesizer, onUpdate);
  }

  ObserverSpeechSession._(this._speechSynthesizer, this._onUpdate);

  final SpeechSynthesizer _speechSynthesizer;
  final void Function(ObserverSpeechCompleted update) _onUpdate;

  ObserverActiveSpeech? _active;
  Future<void>? _runTask;
  Future<AppResult<void>>? _stopTask;
  Future<AppResult<void>>? _closeTask;
  var _latestRunId = 0;
  var _closed = false;
  var _nativeStopRequired = false;
  ObserverSpeechTarget? _stopRequiredTarget;

  /// The utterance whose completion is still pending projection.
  ObserverActiveSpeech? get active => _active;

  /// The comment whose failed native stop remains available for UI recovery.
  int? get stopRequiredCommentIndex => switch (_stopRequiredTarget) {
    ObserverCommentSpeechTarget(:final commentIndex) => commentIndex,
    _ => null,
  };

  /// Message whose failed native stop remains available for UI recovery.
  int? get stopRequiredMessageIndex => switch (_stopRequiredTarget) {
    ObserverMessageSpeechTarget(:final messageIndex) => messageIndex,
    _ => null,
  };

  /// Voice turn whose failed native stop still occupies the speech slot.
  int? get stopRequiredVoiceTurnId => switch (_stopRequiredTarget) {
    ObserverVoiceAnswerSpeechTarget(:final turnId) => turnId,
    _ => null,
  };

  /// Whether speaking, stopping, or an unprojected completion owns the slot.
  bool get isActive => _active != null || _runTask != null || _stopTask != null || _nativeStopRequired;

  /// Starts [text] for a committed [commentIndex] when the slot is idle.
  ObserverActiveSpeech? start({
    required int commentIndex,
    required String text,
  }) {
    return _start(
      target: ObserverCommentSpeechTarget(commentIndex),
      text: text,
    );
  }

  /// Starts [text] for a committed hands-free [turnId] when idle.
  ObserverActiveSpeech? startVoice({
    required int turnId,
    required String text,
  }) {
    return _start(
      target: ObserverVoiceAnswerSpeechTarget(turnId),
      text: text,
    );
  }

  /// Starts [text] for a committed Assistant [messageIndex] when idle.
  ObserverActiveSpeech? startMessage({
    required int messageIndex,
    required String text,
  }) {
    return _start(
      target: ObserverMessageSpeechTarget(messageIndex),
      text: text,
    );
  }

  ObserverActiveSpeech? _start({
    required ObserverSpeechTarget target,
    required String text,
  }) {
    if (_closed || isActive) return null;

    final speech = ObserverActiveSpeech(
      runId: ++_latestRunId,
      target: target,
    );
    _stopRequiredTarget = null;
    _active = speech;
    late final Future<void> task;
    task = _speak(speech, text).whenComplete(() {
      if (identical(_runTask, task)) _runTask = null;
    });
    _runTask = task;
    unawaited(task);
    return speech;
  }

  /// Releases active metadata after the owner consumes [runId]'s completion.
  void complete(int runId) {
    if (_active?.runId == runId) _active = null;
  }

  /// Invalidates the active utterance before stopping the native boundary.
  ///
  /// Concurrent callers share one stop operation. Completion waits for the
  /// invalidated speak task as well, so a later replay cannot inherit a native
  /// callback from the stopped utterance.
  Future<AppResult<void>> stop() {
    final existing = _stopTask;
    if (existing != null) return existing;
    if (!isActive) return Future.value(const AppSuccess<void>(null));

    _stopRequiredTarget ??= _active?.target;
    _active = null;
    _latestRunId += 1;
    _nativeStopRequired = true;
    late final Future<AppResult<void>> task;
    task = _stopOnce()
        .then((result) {
          if (result is AppSuccess<void>) {
            _nativeStopRequired = false;
            _stopRequiredTarget = null;
          }
          return result;
        })
        .whenComplete(() {
          if (identical(_stopTask, task)) _stopTask = null;
        });
    _stopTask = task;
    return task;
  }

  /// Permanently stops callbacks without closing the app-owned synthesizer.
  Future<AppResult<void>> close() {
    final existing = _closeTask;
    if (existing != null) return existing;

    _closed = true;
    _stopRequiredTarget ??= _active?.target;
    _active = null;
    _latestRunId += 1;
    _nativeStopRequired = true;
    late final Future<AppResult<void>> task;
    task = _stopOnce().then((result) {
      if (result is AppSuccess<void>) {
        _nativeStopRequired = false;
        _stopRequiredTarget = null;
      }
      if (result is AppError<void> && identical(_closeTask, task)) {
        _closeTask = null;
      }
      return result;
    });
    _closeTask = task;
    return task;
  }

  Future<void> _speak(
    ObserverActiveSpeech speech,
    String text,
  ) async {
    AppResult<void> result;
    try {
      result = await _speechSynthesizer.speak(text);
    } on Object catch (error, stackTrace) {
      result = AppError(
        UnexpectedFailure(
          code: 'observer_speech_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_closed && _active?.runId == speech.runId) {
      _onUpdate(ObserverSpeechCompleted(speech: speech, result: result));
    }
  }

  Future<AppResult<void>> _stopOnce() async {
    AppResult<void> result;
    try {
      result = await _speechSynthesizer.stop();
    } on Object catch (error, stackTrace) {
      result = AppError(
        UnexpectedFailure(
          code: 'observer_speech_stop_unexpected',
          message: error.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    if (result is AppSuccess<void>) {
      final runTask = _runTask;
      if (runTask != null) await runTask;
    }
    return result;
  }
}
