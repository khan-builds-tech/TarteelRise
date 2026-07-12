import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/services/quran_repository.dart';

void main() {
  const QuranRepository repository = QuranRepository();

  group('hasVerseData', () {
    test('is true for a seeded Surah', () {
      expect(repository.hasVerseData(1), isTrue);
    });

    test('is false for a Surah with only catalog metadata', () {
      expect(repository.hasVerseData(2), isFalse);
    });
  });

  group('buildSession', () {
    test('joins the requested ayah range in order', () {
      final QuranSession session = repository.buildSession(
        surahIndex: 1,
        startAyah: 1,
        requestedAyahCount: 2,
      );

      expect(session.arabicText, 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ');
      expect(session.nextBookmarkAyah, 3);
    });

    test('wraps the bookmark back to 1 after the last ayah', () {
      final QuranSession session = repository.buildSession(
        surahIndex: 112,
        startAyah: 3,
        requestedAyahCount: 2,
      );

      expect(session.nextBookmarkAyah, 1);
    });

    test('falls back to Al-Fatiha for a Surah with no seeded verse text', () {
      final QuranSession session = repository.buildSession(
        surahIndex: 2,
        startAyah: 1,
        requestedAyahCount: 1,
      );

      expect(session.arabicText, 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ');
    });
  });
}
