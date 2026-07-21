/// A normalized wake-phrase match and any question words already recognized.
final class WakePhraseMatch {
  /// Creates a match with the normalized transcript after the wake phrase.
  const WakePhraseMatch({required this.trailingTranscript});

  /// Normalized words recognized after the wake phrase in the same partial.
  final String trailingTranscript;
}

/// Detects an English wake phrase as a complete token sequence.
///
/// Streaming recognizers revise one cumulative hypothesis over time. Callers
/// may therefore pass every revision to [detect]; partial prefixes such as
/// `assi` and longer words such as `assistance` never match `assistant`.
final class WakePhraseDetector {
  /// Creates a detector for one non-empty [wakePhrase].
  WakePhraseDetector(String wakePhrase) : _wakeTokens = _normalize(wakePhrase) {
    if (_wakeTokens.isEmpty) {
      throw ArgumentError.value(
        wakePhrase,
        'wakePhrase',
        'The wake phrase must contain at least one English letter or digit.',
      );
    }
  }

  final List<String> _wakeTokens;

  /// Returns the first whole-token match in [transcript], if present.
  ///
  /// Punctuation, casing, and repeated whitespace are ignored. The trailing
  /// transcript is normalized as well so a phrase such as
  /// `Assistant, what can you see?` can seed the listening turn without
  /// losing words already decoded in the wake hypothesis.
  WakePhraseMatch? detect(String transcript) {
    final tokens = _normalize(transcript);
    if (tokens.length < _wakeTokens.length) return null;

    final lastStart = tokens.length - _wakeTokens.length;
    for (var start = 0; start <= lastStart; start += 1) {
      var matches = true;
      for (var offset = 0; offset < _wakeTokens.length; offset += 1) {
        if (tokens[start + offset] != _wakeTokens[offset]) {
          matches = false;
          break;
        }
      }
      if (!matches) continue;
      return WakePhraseMatch(
        trailingTranscript: tokens.skip(start + _wakeTokens.length).join(' '),
      );
    }
    return null;
  }
}

List<String> _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}
