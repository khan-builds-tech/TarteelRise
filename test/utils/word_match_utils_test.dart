import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/utils/word_match_utils.dart';

void main() {
  group('wordMatchFlags', () {
    test('flags every word true on an exact match', () {
      expect(
        wordMatchFlags(['a', 'b', 'c'], ['a', 'b', 'c']),
        [true, true, true],
      );
    });

    test('flags only the words actually recognized, preserving order', () {
      expect(
        wordMatchFlags(['a', 'b', 'c'], ['a', 'c']),
        [true, false, true],
      );
    });

    test('flags a repeated word only as many times as it was recognized', () {
      expect(
        wordMatchFlags(['x', 'x', 'x'], ['x', 'x']),
        [true, true, false],
      );
    });

    test('returns an empty list for an empty original list', () {
      expect(wordMatchFlags([], ['a', 'b']), <bool>[]);
    });
  });

  group('percentageFromFlags', () {
    test('returns 0.0 for an empty list instead of dividing by zero', () {
      expect(percentageFromFlags(<bool>[]), 0.0);
    });

    test('returns the proportion of true flags as a percentage', () {
      expect(percentageFromFlags([true, true, false, false]), 50.0);
    });

    test('returns 100.0 when every flag is true', () {
      expect(percentageFromFlags([true, true]), 100.0);
    });
  });
}
