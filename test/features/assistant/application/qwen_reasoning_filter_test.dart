import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/services/qwen_reasoning_filter.dart';

void main() {
  test('hides reasoning and control tags at every three-chunk boundary', () {
    const raw = '<think>private chain</think>\n\nVisible answer.';

    for (var first = 0; first <= raw.length; first += 1) {
      for (var second = first; second <= raw.length; second += 1) {
        final filter = QwenReasoningFilter();
        final fragments = [
          filter.add(raw.substring(0, first)),
          filter.add(raw.substring(first, second)),
          filter.add(raw.substring(second)),
          filter.finish(),
        ];
        final visible = fragments.join();

        expect(
          visible,
          'Visible answer.',
          reason: 'Unexpected output for split ($first, $second).',
        );
        expect(fragments, isNot(contains('<think>')));
        expect(visible, isNot(contains('private chain')));
      }
    }
  });

  test('removes an empty no-think block split one character at a time', () {
    const raw = '<think>\n\n</think>\n\nDirect answer.';
    final filter = QwenReasoningFilter();
    final visible = StringBuffer();

    for (final codeUnit in raw.codeUnits) {
      visible.write(filter.add(String.fromCharCode(codeUnit)));
    }
    visible.write(filter.finish());

    expect(visible.toString(), 'Direct answer.');
  });

  test(
    'hides prefilled reasoning without an opening tag at every chunk boundary',
    () {
      const raw = 'private chain</think>\n\nVisible answer.';

      for (var first = 0; first <= raw.length; first += 1) {
        for (var second = first; second <= raw.length; second += 1) {
          final filter = QwenReasoningFilter(startsInsideReasoning: true);
          final fragments = [
            filter.add(raw.substring(0, first)),
            filter.add(raw.substring(first, second)),
            filter.add(raw.substring(second)),
            filter.finish(),
          ];
          final visible = fragments.join();

          expect(
            visible,
            'Visible answer.',
            reason: 'Unexpected output for split ($first, $second).',
          );
          expect(visible, isNot(contains('private chain')));
        }
      }
    },
  );

  test('streams ordinary text without waiting for completion', () {
    final filter = QwenReasoningFilter();

    expect(filter.add('Ordinary '), 'Ordinary ');
    expect(filter.add('answer.'), 'answer.');
    expect(filter.finish(), isEmpty);
  });

  test('removes multiple reasoning blocks and their separators', () {
    expect(
      QwenReasoningFilter.filterComplete(
        '<think>one</think>\n\nFirst. '
        '<think>two</think>\nSecond.',
      ),
      'First. Second.',
    );
  });

  test('drops output before a closing tag injected by the prompt template', () {
    expect(
      QwenReasoningFilter.filterComplete(
        'private chain without opening</think>\n\nPublic answer.',
      ),
      'Public answer.',
    );
  });

  test('drops an unterminated reasoning block and finishes once', () {
    final filter = QwenReasoningFilter();

    expect(filter.add('<think>unfinished private chain'), isEmpty);
    expect(filter.finish(), isEmpty);
    expect(filter.finish(), isEmpty);
    expect(() => filter.add('late'), throwsStateError);
  });

  test('does not flush a proper prefix of either control tag', () {
    for (final marker in const ['<think>', '</think>']) {
      for (var length = 1; length < marker.length; length += 1) {
        final filter = QwenReasoningFilter();
        final prefix = marker.substring(0, length);
        final visible = '${filter.add('Answer $prefix')}${filter.finish()}';

        expect(
          visible,
          'Answer ',
          reason: 'Leaked the terminal marker prefix "$prefix".',
        );
      }
    }
  });
}
