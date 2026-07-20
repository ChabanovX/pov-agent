/// Incrementally extracts the first substantive complete English sentence.
///
/// A terminal boundary remains pending until visible look-ahead or native end
/// confirms it, allowing closing quotes and brackets split across chunks to be
/// retained. Common abbreviations and decimal points are not treated as
/// sentence boundaries. Terse preambles such as `Sure!` are discarded.
final class FirstCompleteEnglishSentenceAccumulator {
  static final RegExp _englishWord = RegExp(
    r"\b[A-Za-z]+(?:['’][A-Za-z]+)?\b",
  );
  static final RegExp _obviousNonLatinScript = RegExp(
    r'[\u0370-\u052F\u0590-\u08FF\u0900-\u097F\u3040-\u30FF'
    r'\u3400-\u9FFF\uAC00-\uD7AF]',
  );
  static const _commonAbbreviations = {
    'dr',
    'e.g',
    'etc',
    'fig',
    'i.e',
    'jr',
    'mr',
    'mrs',
    'ms',
    'no',
    'prof',
    'sr',
    'st',
    'u.k',
    'u.s',
    'vs',
  };
  static const _terminalPunctuation = '.!?';
  static const _closingDelimiters = '"\'”’»)]}';

  String _pending = '';
  bool _finished = false;

  /// Adds visible model output and returns the sentence once its boundary is
  /// stable, or `null` while more output is required.
  String? add(String chunk) {
    if (_finished) {
      throw StateError('Cannot add output after sentence accumulation finished.');
    }
    if (chunk.isEmpty) return null;
    _pending += chunk;
    return _drain(atNativeEnd: false);
  }

  /// Marks native output complete and returns a terminal sentence if present.
  ///
  /// An incomplete or non-English remainder is rejected with `null`.
  String? finish() {
    if (_finished) return null;
    final sentence = _drain(atNativeEnd: true);
    _finished = true;
    return sentence;
  }

  String? _drain({required bool atNativeEnd}) {
    while (_pending.isNotEmpty) {
      final boundaryEnd = _findBoundaryEnd(atNativeEnd: atNativeEnd);
      if (boundaryEnd == null) return null;

      final candidate = _pending.substring(0, boundaryEnd).trim();
      _pending = _pending.substring(boundaryEnd).trimLeft();
      if (!_isSubstantiveEnglish(candidate)) continue;

      _finished = true;
      _pending = '';
      return candidate;
    }
    return null;
  }

  int? _findBoundaryEnd({required bool atNativeEnd}) {
    for (var index = 0; index < _pending.length; index += 1) {
      if (!_terminalPunctuation.contains(_pending[index])) continue;

      var punctuationEnd = index + 1;
      while (punctuationEnd < _pending.length && _terminalPunctuation.contains(_pending[punctuationEnd])) {
        punctuationEnd += 1;
      }
      if (punctuationEnd == index + 1 &&
          _pending[index] == '.' &&
          _isNonTerminalPeriod(index, atNativeEnd: atNativeEnd)) {
        continue;
      }

      var boundaryEnd = punctuationEnd;
      while (boundaryEnd < _pending.length && _closingDelimiters.contains(_pending[boundaryEnd])) {
        boundaryEnd += 1;
      }

      // Without visible look-ahead, a later chunk may still contain a closing
      // quote or another punctuation mark belonging to this same boundary.
      if (boundaryEnd == _pending.length && !atNativeEnd) return null;
      if (boundaryEnd < _pending.length && _pending[boundaryEnd].trim().isNotEmpty) {
        continue;
      }
      return boundaryEnd;
    }
    return null;
  }

  bool _isNonTerminalPeriod(int index, {required bool atNativeEnd}) {
    final previous = index == 0 ? null : _pending[index - 1];
    final next = index + 1 == _pending.length ? null : _pending[index + 1];
    if (_isDigit(previous) && _isDigit(next)) return true;
    if (_isAsciiLetter(previous) && _isAsciiLetter(next)) return true;

    final token = _tokenBefore(index).toLowerCase();
    final isAbbreviation = _commonAbbreviations.contains(token) || token.length == 1;
    if (!isAbbreviation) return false;

    final remainder = _pending.substring(index + 1).trim();
    // Unlike titles such as `Dr.`, `etc.` commonly closes a sentence. Once a
    // capitalized next sentence is visible, prefer that stable interpretation.
    if (token == 'etc' && remainder.isNotEmpty && _isAsciiUppercase(remainder[0])) {
      return false;
    }
    return !atNativeEnd || remainder.isNotEmpty;
  }

  String _tokenBefore(int boundaryIndex) {
    var start = boundaryIndex;
    while (start > 0) {
      final character = _pending[start - 1];
      if (!_isAsciiLetter(character) && character != '.') break;
      start -= 1;
    }
    return _pending.substring(start, boundaryIndex);
  }

  bool _isSubstantiveEnglish(String candidate) {
    return !_obviousNonLatinScript.hasMatch(candidate) && _englishWord.allMatches(candidate).length >= 3;
  }
}

bool _isAsciiLetter(String? character) {
  if (character == null || character.length != 1) return false;
  final codeUnit = character.codeUnitAt(0);
  return (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);
}

bool _isAsciiUppercase(String? character) {
  if (character == null || character.length != 1) return false;
  final codeUnit = character.codeUnitAt(0);
  return codeUnit >= 65 && codeUnit <= 90;
}

bool _isDigit(String? character) {
  if (character == null || character.length != 1) return false;
  final codeUnit = character.codeUnitAt(0);
  return codeUnit >= 48 && codeUnit <= 57;
}
