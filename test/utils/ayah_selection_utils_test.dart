import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/utils/ayah_selection_utils.dart';

void main() {
  group('wordCount', () {
    test('counts words separated by single spaces', () {
      expect(wordCount('بِسْمِ اللَّهِ الرَّحْمَٰنِ'), 3);
    });

    test('collapses runs of internal whitespace', () {
      expect(wordCount('one   two\tthree'), 3);
    });

    test('returns 0 for empty or blank text', () {
      expect(wordCount(''), 0);
      expect(wordCount('   '), 0);
    });
  });

  group('pickRandomIndexWithinWordLimit', () {
    test('only ever returns an index whose word count is within the limit', () {
      final List<int> wordCounts = [12, 3, 20, 5, 1, 15];
      final Random random = Random(42);

      for (int i = 0; i < 50; i++) {
        final int index = pickRandomIndexWithinWordLimit(
          wordCounts: wordCounts,
          maxWords: 10,
          random: random,
        );
        expect(wordCounts[index], lessThanOrEqualTo(10));
      }
    });

    test('is deterministic for a given seed', () {
      final List<int> wordCounts = [2, 4, 6, 8];

      final int first = pickRandomIndexWithinWordLimit(
        wordCounts: wordCounts,
        maxWords: 10,
        random: Random(7),
      );
      final int second = pickRandomIndexWithinWordLimit(
        wordCounts: wordCounts,
        maxWords: 10,
        random: Random(7),
      );

      expect(first, second);
    });

    test('falls back to the shortest candidate when none qualify', () {
      final List<int> wordCounts = [50, 40, 12, 60];

      final int index = pickRandomIndexWithinWordLimit(
        wordCounts: wordCounts,
        maxWords: 10,
        random: Random(1),
        maxAttempts: 5,
      );

      expect(index, 2); // The only 12-word entry is the shortest available.
    });

    test('throws for an empty candidate list', () {
      expect(
        () => pickRandomIndexWithinWordLimit(
          wordCounts: const <int>[],
          maxWords: 10,
          random: Random(),
        ),
        throwsArgumentError,
      );
    });
  });
}
