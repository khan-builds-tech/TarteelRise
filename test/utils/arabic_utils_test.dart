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
}
