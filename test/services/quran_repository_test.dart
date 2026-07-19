import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/data/quran_verses.dart';
import 'package:tarteel_rise/data/surah_catalog.dart';
import 'package:tarteel_rise/services/quran_repository.dart';
import 'package:tarteel_rise/utils/ayah_selection_utils.dart';

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

  group('buildRandomChallenge', () {
    test('always returns text belonging to a real verse of the requested Surah', () {
      final List<AyahRecord> verses = repository.versesFor(1);
      final Set<String> realArabicTexts = verses.map((v) => v.text).toSet();
      final Set<String> realTranslations = verses.map((v) => v.translation).toSet();

      // Repeated to exercise different random rolls rather than relying
      // on a single draw.
      for (int i = 0; i < 30; i++) {
        final QuranSession session = repository.buildRandomChallenge(surahIndex: 1);
        expect(realArabicTexts, contains(session.arabicText));
        expect(realTranslations, contains(session.translation));
      }
    });

    test('never returns an ayah longer than maxChallengeAyahWords', () {
      // Al-Baqarah (286 ayahs) has a wide mix of short and very long
      // verses — a good stress case for the word-count rejection.
      for (int i = 0; i < 30; i++) {
        final QuranSession session = repository.buildRandomChallenge(surahIndex: 2);
        expect(wordCount(session.arabicText), lessThanOrEqualTo(QuranRepository.maxChallengeAyahWords));
      }
    });

    test('falls back to Al-Fatiha when the requested Surah has no verse data', () {
      final QuranRepository unloaded = QuranRepository();
      // Never awaited loadFromAssets — surahById/versesFor return nothing
      // for any id, including Al-Fatiha itself, so the safe empty-text
      // fallback is what's actually reachable here.
      final QuranSession session = unloaded.buildRandomChallenge(surahIndex: 5);

      expect(session.arabicText, '');
      expect(session.translation, '');
    });
  });
}
