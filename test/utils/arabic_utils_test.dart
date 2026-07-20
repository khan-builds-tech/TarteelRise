import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/utils/arabic_utils.dart';

void main() {
  group('normalizeArabicText', () {
    test('strips full Tashkeel diacritics to match undiacritized text', () {
      const String withVowels = 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ';
      const String withoutVowels = 'بسم الله الرحمن الرحيم';

      expect(normalizeArabicText(withVowels), normalizeArabicText(withoutVowels));
    });

    test('normalizes all Alef variants (إ أ آ) to a bare Alef', () {
      expect(normalizeArabicText('إن أحدا آمن'), 'ان احدا امن');
    });

    test('collapses irregular internal whitespace and trims edges', () {
      const String messySpacing = '  الحمد   لله   رب  العالمين  ';
      expect(normalizeArabicText(messySpacing), 'الحمد لله رب العالمين');
    });

    test('is idempotent on already-normalized text', () {
      const String clean = 'الرحمن الرحيم';
      expect(normalizeArabicText(clean), clean);
    });

    test('folds Alef Wasla (ٱ) to a bare Alef, not just إ/أ/آ', () {
      // The bundled Quran dataset (assets/data/quran_en.json) is written in
      // Uthmani script, which spells "the" (ال-) with Alef Wasla almost
      // everywhere — e.g. "ٱللَّهِ" — while spoken/STT-transcribed
      // recitation says the plain form, "الله". Regression test for a real
      // bug: Wasla wasn't in the original Alef-folding regex at all.
      expect(normalizeArabicText('ٱللَّهِ'), normalizeArabicText('الله'));
    });

    test('strips Quranic small-mark diacritics beyond basic Tashkeel', () {
      // U+06E1 (ARABIC SMALL HIGH DOTLESS HEAD OF KHAH) appears ~37,000
      // times in the bundled dataset and is outside the basic
      // Fatha-through-Sukun range — a real gap in the original diacritics
      // regex.
      expect(normalizeArabicText('بِسۡمِ'), 'بسم');
    });

    test('folds dagger Alif (superscript Alef) to a real Alef, not deletes it', () {
      // Dagger Alif represents an actual long "aa" vowel sound (e.g.
      // "ٱلۡعَٰلَمِينَ" is pronounced "al-'aalameen") rather than a mere
      // pronunciation modifier — deleting it instead of folding it to Alef
      // was a regression found while fixing the Wasla bug above: it turned
      // "العالمين" into "العلمين", a real word-level mismatch.
      expect(normalizeArabicText('ٱلۡعَٰلَمِينَ'), normalizeArabicText('العالمين'));
      expect(normalizeArabicText('صِرَٰطَ'), normalizeArabicText('صراط'));
    });

    test('drops Tatweel (kashida) without affecting the surrounding letters', () {
      expect(normalizeArabicText('بِسْـــمِ اللَّه'), normalizeArabicText('بسم الله'));
    });

    test('strips digits and stray punctuation', () {
      expect(normalizeArabicText('الحمد، لله! ١٢٣'), 'الحمد لله');
    });
  });

  group('calculateMatchPercentage', () {
    test('returns 100.0 for an exact match after normalization', () {
      const String original = 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ';
      const String recognized = 'بسم الله الرحمن الرحيم';

      expect(calculateMatchPercentage(original, recognized), 100.0);
    });

    test('tolerates Alef-variant and spacing drift as a full match', () {
      const String original = 'إن أحدا آمن';
      const String recognized = '  ان   احدا امن  ';

      expect(calculateMatchPercentage(original, recognized), 100.0);
    });

    test('scores a partial word match proportionally (Easy-mode threshold)', () {
      // 3 of 4 reference words recognized -> 75%, clears Easy (>=65%) but not Medium (>=80%).
      const String original = 'الحمد للّه رب العالمين';
      const String recognized = 'الحمد للّه رب';

      expect(calculateMatchPercentage(original, recognized), 75.0);
    });

    test('returns 0.0 when nothing recognized matches the reference', () {
      const String original = 'الحمد للّه رب العالمين';
      const String recognized = 'وقالوا سبحان ربنا';

      expect(calculateMatchPercentage(original, recognized), 0.0);
    });

    test('returns 0.0 for an empty reference string instead of dividing by zero', () {
      expect(calculateMatchPercentage('', 'بسم الله'), 0.0);
    });
  });

  group('matchedWordFlags', () {
    test('flags every word true on an exact match', () {
      const String original = 'الحمد لله رب العالمين';
      expect(matchedWordFlags(original, original), [true, true, true, true]);
    });

    test('flags only the words actually recognized, preserving order', () {
      const String original = 'الحمد لله رب العالمين';
      const String recognized = 'الحمد رب';

      expect(matchedWordFlags(original, recognized), [true, false, true, false]);
    });

    test('flags a repeated word only as many times as it was recognized', () {
      const String original = 'الله الله الله';
      const String recognized = 'الله الله';

      expect(matchedWordFlags(original, recognized), [true, true, false]);
    });

    test('returns an empty list for an empty reference string', () {
      expect(matchedWordFlags('', 'بسم الله'), <bool>[]);
    });
  });
}
