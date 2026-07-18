import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/data/quran_verses.dart';
import 'package:tarteel_rise/data/surah_catalog.dart';
import 'package:tarteel_rise/services/quran_repository.dart';

void main() {
  // `rootBundle.loadString` (inside `loadFromAssets`) needs the Flutter
  // test binding — plain `test()` (unlike `testWidgets()`) doesn't set
  // this up automatically.
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranRepository repository;

  setUpAll(() async {
    repository = QuranRepository();
    await repository.loadFromAssets();
  });

  test('loadFromAssets parses the full 114-Surah catalog', () {
    expect(repository.isLoaded, isTrue);
    expect(repository.allSurahs.length, 114);
  });

  group('surahById', () {
    test('returns real catalog metadata', () {
      final Surah? ikhlas = repository.surahById(112);
      expect(ikhlas, isNotNull);
      expect(ikhlas!.transliteration, 'Al-Ikhlas');
      expect(ikhlas.name, 'الإخلاص');
      expect(ikhlas.totalVerses, 4);
    });

    test('returns null for an id outside 1-114', () {
      expect(repository.surahById(115), isNull);
    });
  });

  group('hasVerseData', () {
    test('is true for every Surah now that the full dataset is loaded', () {
      // Previously only 4 Surahs (of the 15-entry starter catalog) had
      // real verse text; now every Surah 1-114 does.
      expect(repository.hasVerseData(1), isTrue);
      expect(repository.hasVerseData(2), isTrue);
      expect(repository.hasVerseData(114), isTrue);
    });
  });

  group('buildSession', () {
    test('joins the requested ayah range in order, Arabic and translation', () {
      // Compares against the repository's own already-parsed cache for
      // ayahs 1-2, rather than a hand-copied literal — this is testing
      // buildSession's selection/join/ordering logic, not transcribing
      // Arabic combining diacritics by hand into Dart source (a real,
      // easy-to-get-wrong risk that isn't what this test is meant to
      // catch; the dataset's own religious-text accuracy is out of scope
      // here).
      final List<AyahRecord> verses = repository.versesFor(1);
      final AyahRecord ayah1 = verses.firstWhere((v) => v.id == 1);
      final AyahRecord ayah2 = verses.firstWhere((v) => v.id == 2);

      final QuranSession session = repository.buildSession(
        surahIndex: 1,
        startAyah: 1,
        requestedAyahCount: 2,
      );

      expect(session.arabicText, '${ayah1.text} ${ayah2.text}');
      expect(session.translation, '${ayah1.translation} ${ayah2.translation}');
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

    test('recites the real text of a long Surah instead of falling back to Al-Fatiha', () {
      // Al-Baqarah (286 ayahs) had no seeded verse text under the old
      // static starter catalog, so this used to silently substitute
      // Al-Fatiha. The full dataset covers it for real now.
      final AyahRecord baqarahAyah1 = repository.versesFor(2).firstWhere((v) => v.id == 1);

      final QuranSession session = repository.buildSession(
        surahIndex: 2,
        startAyah: 1,
        requestedAyahCount: 1,
      );

      expect(session.arabicText, baqarahAyah1.text);
      expect(session.arabicText, isNot('')); // Never the Al-Fatiha fallback.
    });
  });
}
