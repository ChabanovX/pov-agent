/// Incrementally removes Qwen `<think>...</think>` blocks from model output.
///
/// Partial tag prefixes are retained between [add] calls, so neither reasoning
/// nor fragments of a control tag can flash in streaming presentation.
final class QwenReasoningFilter {
  /// Creates a filter for an ordinary or prompt-prefilled token stream.
  QwenReasoningFilter({bool startsInsideReasoning = false}) : _insideReasoning = startsInsideReasoning;

  static const _openingTag = '<think>';
  static const _closingTag = '</think>';

  String _pending = '';
  bool _insideReasoning;
  bool _trimAnswerSeparator = false;
  bool _finished = false;

  /// Adds one decoded model [chunk] and returns newly visible answer text.
  String add(String chunk) {
    if (_finished) {
      throw StateError('Cannot add output after the reasoning filter finished.');
    }
    if (chunk.isEmpty) return '';
    _pending += chunk;
    return _drain(flush: false);
  }

  /// Flushes remaining ordinary text and permanently finishes this filter.
  ///
  /// An unterminated reasoning block is discarded rather than exposed.
  String finish() {
    if (_finished) return '';
    _finished = true;
    return _drain(flush: true);
  }

  /// Removes reasoning from one already completed model response.
  ///
  /// Qwen templates may inject the opening tag into the generation prompt. If
  /// output therefore contains only `</think>`, everything before its final
  /// occurrence is treated as reasoning and excluded.
  static String filterComplete(String output) {
    var candidate = output;
    final firstOpening = candidate.indexOf(_openingTag);
    final lastClosing = candidate.lastIndexOf(_closingTag);
    if (firstOpening == -1 && lastClosing != -1) {
      candidate = _removeLeadingLineBreaks(
        candidate.substring(lastClosing + _closingTag.length),
      );
    }

    final filter = QwenReasoningFilter();
    return '${filter.add(candidate)}${filter.finish()}';
  }

  String _drain({required bool flush}) {
    final visible = StringBuffer();

    while (_pending.isNotEmpty) {
      if (_insideReasoning) {
        final closingIndex = _pending.indexOf(_closingTag);
        if (closingIndex == -1) {
          if (flush) {
            _pending = '';
          } else {
            _pending = _suffixThatMayStart(_pending, _closingTag);
          }
          break;
        }

        _pending = _pending.substring(closingIndex + _closingTag.length);
        _insideReasoning = false;
        _trimAnswerSeparator = true;
        continue;
      }

      if (_trimAnswerSeparator) {
        _pending = _removeLeadingLineBreaks(_pending);
        if (_pending.isEmpty) break;
        _trimAnswerSeparator = false;
      }

      final openingIndex = _pending.indexOf(_openingTag);
      final closingIndex = _pending.indexOf(_closingTag);
      final marker = _firstMarker(openingIndex, closingIndex);
      if (marker != null) {
        visible.write(_pending.substring(0, marker.index));
        _pending = _pending.substring(marker.index + marker.tag.length);
        if (marker.tag == _openingTag) {
          _insideReasoning = true;
        } else {
          // A stray closing tag is a control token, never display text.
          _trimAnswerSeparator = true;
        }
        continue;
      }

      if (flush) {
        // Streaming retained this suffix only because it could become a
        // control tag. At end of stream it is safer to discard the malformed
        // marker than expose a tag fragment as answer text.
        _pending = '';
        break;
      }

      final retainedLength = _possibleMarkerSuffixLength(_pending);
      final visibleLength = _pending.length - retainedLength;
      if (visibleLength > 0) {
        visible.write(_pending.substring(0, visibleLength));
      }
      _pending = _pending.substring(visibleLength);
      break;
    }

    return visible.toString();
  }

  int _possibleMarkerSuffixLength(String value) {
    final openingSuffix = _suffixThatMayStart(value, _openingTag).length;
    final closingSuffix = _suffixThatMayStart(value, _closingTag).length;
    return openingSuffix > closingSuffix ? openingSuffix : closingSuffix;
  }
}

({int index, String tag})? _firstMarker(
  int openingIndex,
  int closingIndex,
) {
  if (openingIndex == -1 && closingIndex == -1) return null;
  if (openingIndex == -1) return (index: closingIndex, tag: '</think>');
  if (closingIndex == -1 || openingIndex < closingIndex) {
    return (index: openingIndex, tag: '<think>');
  }
  return (index: closingIndex, tag: '</think>');
}

String _suffixThatMayStart(String value, String marker) {
  final maxLength = value.length < marker.length - 1 ? value.length : marker.length - 1;
  for (var length = maxLength; length > 0; length -= 1) {
    final suffix = value.substring(value.length - length);
    if (marker.startsWith(suffix)) return suffix;
  }
  return '';
}

String _removeLeadingLineBreaks(String value) {
  var index = 0;
  while (index < value.length) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit != 10 && codeUnit != 13) break;
    index += 1;
  }
  return index == 0 ? value : value.substring(index);
}
