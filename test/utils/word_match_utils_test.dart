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

    test('flags a word true when recognized with one substituted letter', () {
      expect(
        wordMatchFlags(['alameen'], ['alamein']),
        [true],
      );
    });

    test('flags a word true when recognized with one dropped letter', () {
      expect(
        wordMatchFlags(['rahman'], ['rahmn']),
        [true],
      );
    });

    test('does not fuzzy-match short words a single edit apart', () {
      expect(
        wordMatchFlags(['in'], ['on']),
        [false],
      );
    });

    test('does not fuzzy-match words that differ by too many edits', () {
      expect(
        wordMatchFlags(['rahman'], ['xyz']),
        [false],
      );
    });

    test('prefers an exact match over stealing it via fuzzy match', () {
      // 'rahman' fuzzy-matches 'rahmaan' too, but the exact 'rahman' in
      // recognizedWords must be consumed first so the fuzzy match remains
      // available for a second original word that needs it.
      expect(
        wordMatchFlags(['rahman', 'rahmaan'], ['rahmaan', 'rahman']),
        [true, true],
      );
    });
  });

  group('levenshteinDistance', () {
    test('returns 0 for identical strings', () {
      expect(levenshteinDistance('same', 'same'), 0);
    });

    test('returns the length of the other string when one is empty', () {
      expect(levenshteinDistance('', 'abc'), 3);
      expect(levenshteinDistance('abc', ''), 3);
    });

    test('counts a single substitution as distance 1', () {
      expect(levenshteinDistance('cat', 'cot'), 1);
    });

    test('counts a single insertion/deletion as distance 1', () {
      expect(levenshteinDistance('cat', 'cats'), 1);
    });
  });

  group('isFuzzyWordMatch', () {
    test('requires an exact match for words 2 characters or fewer', () {
      expect(isFuzzyWordMatch('in', 'on'), false);
      expect(isFuzzyWordMatch('in', 'in'), true);
    });

    test('allows 1 edit for words up to 4 characters', () {
      expect(isFuzzyWordMatch('cat', 'cot'), true);
      expect(isFuzzyWordMatch('cats', 'cots'), true);
    });

    test('allows 2 edits for words 5 characters or longer', () {
      expect(isFuzzyWordMatch('rahman', 'rahmaan'), true);
    });

    test('rejects words beyond the allowed edit budget', () {
      expect(isFuzzyWordMatch('rahman', 'xyz'), false);
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
