import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/utils/bookmark_utils.dart';

void main() {
  group('ayahNumbersForSession', () {
    test('returns a consecutive run of the requested length', () {
      final List<int> ayahs = ayahNumbersForSession(
        startAyah: 3,
        requestedCount: 4,
        totalAyahsInSurah: 20,
      );
      expect(ayahs, [3, 4, 5, 6]);
    });

    test('clamps to the end of the Surah instead of overrunning it', () {
      final List<int> ayahs = ayahNumbersForSession(
        startAyah: 5,
        requestedCount: 5,
        totalAyahsInSurah: 7,
      );
      expect(ayahs, [5, 6, 7]);
    });

    test('returns just the start ayah when already at the last one', () {
      final List<int> ayahs = ayahNumbersForSession(
        startAyah: 7,
        requestedCount: 3,
        totalAyahsInSurah: 7,
      );
      expect(ayahs, [7]);
    });
  });

  group('computeNextBookmark', () {
    test('continues to the next ayah when the Surah has more left', () {
      expect(
        computeNextBookmark(lastAyahRead: 6, totalAyahsInSurah: 30),
        7,
      );
    });

    test('wraps back to 1 once the Surah is exhausted', () {
      expect(
        computeNextBookmark(lastAyahRead: 30, totalAyahsInSurah: 30),
        1,
      );
    });
  });
}
