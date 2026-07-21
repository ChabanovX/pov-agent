import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/application/services/wake_phrase_detector.dart';

void main() {
  group('WakePhraseDetector', () {
    test('matches casing and punctuation and retains trailing words', () {
      final detector = WakePhraseDetector('assistant');

      final match = detector.detect(
        '  ASSISTANT,   what can you see in front of the camera? ',
      );

      expect(match, isNotNull);
      expect(
        match!.trailingTranscript,
        'what can you see in front of the camera',
      );
    });

    test('waits for a complete wake token across cumulative revisions', () {
      final detector = WakePhraseDetector('assistant');

      expect(detector.detect('assi'), isNull);
      expect(detector.detect('assistant'), isNotNull);
    });

    test('does not match a wake phrase embedded in a longer word', () {
      final detector = WakePhraseDetector('assistant');

      expect(detector.detect('This assistance is useful'), isNull);
      expect(detector.detect('An assistantship program'), isNull);
    });

    test('supports a multi-token wake phrase', () {
      final detector = WakePhraseDetector('hey assistant');

      expect(detector.detect('hey there assistant'), isNull);
      expect(
        detector.detect('Hey, assistant: describe this')?.trailingTranscript,
        'describe this',
      );
    });

    test('rejects a wake phrase without English tokens', () {
      expect(
        () => WakePhraseDetector('---'),
        throwsArgumentError,
      );
    });
  });
}
