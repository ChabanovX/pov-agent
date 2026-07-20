import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/services/first_complete_english_sentence_accumulator.dart';

void main() {
  test('retains a quoted boundary split across every chunk position', () {
    const raw = 'Sure! “A person is visible.” Extra sentence.';

    for (var split = 0; split <= raw.length; split += 1) {
      final accumulator = FirstCompleteEnglishSentenceAccumulator();
      final first = accumulator.add(raw.substring(0, split));
      final sentence = first ?? accumulator.add(raw.substring(split));

      expect(
        sentence ?? accumulator.finish(),
        '“A person is visible.”',
        reason: 'Unexpected sentence for split $split.',
      );
    }
  });

  test('does not split common abbreviations or decimal numbers', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(
      accumulator.add('Dr. Lee sees version 3.14 clearly. Next thought.'),
      'Dr. Lee sees version 3.14 clearly.',
    );
  });

  test('allows etc to close a sentence before a capitalized next one', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(
      accumulator.add('Objects include bags, etc. A person enters.'),
      'Objects include bags, etc.',
    );
  });

  test('keeps punctuation runs and discards a terse preamble', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(
      accumulator.add('Really?! A person appears... Then another.'),
      'A person appears...',
    );
  });

  test('retains a closing bracket after terminal punctuation', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(
      accumulator.add('A person (is visible.) Another thought.'),
      'A person (is visible.)',
    );
  });

  test('does not accept punctuation glued to a word continuation', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(accumulator.add('A person is visible!nearby'), isNull);
    expect(accumulator.finish(), isNull);
  });

  test('does not inflate word count at a typographic apostrophe', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(accumulator.add('A person’s.'), isNull);
    expect(accumulator.finish(), isNull);
  });

  test('uses native end to confirm a boundary without look-ahead', () {
    final accumulator = FirstCompleteEnglishSentenceAccumulator();

    expect(accumulator.add('“A person is visible.”'), isNull);
    expect(accumulator.finish(), '“A person is visible.”');
    expect(accumulator.finish(), isNull);
  });

  test('rejects incomplete and non-English terminal output', () {
    final incomplete = FirstCompleteEnglishSentenceAccumulator();
    final nonEnglish = FirstCompleteEnglishSentenceAccumulator();

    expect(incomplete.add('A person remains partially described'), isNull);
    expect(incomplete.finish(), isNull);
    expect(nonEnglish.add('Человек стоит рядом.'), isNull);
    expect(nonEnglish.finish(), isNull);
  });
}
