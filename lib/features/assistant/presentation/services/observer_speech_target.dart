/// A committed transcript entry that may own the single speech slot.
sealed class ObserverSpeechTarget {
  /// Defines target metadata retained across asynchronous playback.
  const ObserverSpeechTarget();
}

/// One append-only automatic comment selected for speech.
final class ObserverCommentSpeechTarget extends ObserverSpeechTarget {
  /// Creates a target for [commentIndex].
  const ObserverCommentSpeechTarget(this.commentIndex);

  /// Append-only index in the automatic comment transcript.
  final int commentIndex;
}

/// One append-only committed Assistant message selected for replay.
final class ObserverMessageSpeechTarget extends ObserverSpeechTarget {
  /// Creates a target for [messageIndex].
  const ObserverMessageSpeechTarget(this.messageIndex);

  /// Append-only index in the dialogue transcript.
  final int messageIndex;
}

/// One committed hands-free answer selected for mandatory speech.
final class ObserverVoiceAnswerSpeechTarget extends ObserverSpeechTarget {
  /// Creates a target for the monotonic [turnId].
  const ObserverVoiceAnswerSpeechTarget(this.turnId);

  /// Voice turn that produced the committed answer.
  final int turnId;
}
