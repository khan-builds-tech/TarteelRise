import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/utils/translation_match_utils.dart';

void main() {
  group('normalizeEnglishText', () {
    test('lowercases and strips punctuation, including brackets', () {
      const String original = '[All] praise is [due] to Allah, Lord of the worlds -';
      expect(
        normalizeEnglishText(original),
        'all praise is due to allah lord of the worlds',
      );
    });

    test('strips quotation marks used around spoken translations', () {
      expect(
        normalizeEnglishText('Say, "He is Allah, [who is] One,'),
        'say he is allah who is one',
      );
    });

    test('collapses irregular whitespace', () {
      expect(normalizeEnglishText('  He   neither   begets  '), 'he neither begets');
    });
  });

  group('calculateTranslationMatchPercentage', () {
    test('returns 100.0 for a case-insensitive exact match', () {
      const String original = 'It is You we worship and You we ask for help.';
      const String recognized = 'it is you we worship and you we ask for help';
      expect(calculateTranslationMatchPercentage(original, recognized), 100.0);
    });

    test('ignores bracketed clarifying words missing from natural speech', () {
      const String original = '[All] praise is [due] to Allah, Lord of the worlds -';
      const String recognized = 'all praise is due to allah lord of the worlds';
      expect(calculateTranslationMatchPercentage(original, recognized), 100.0);
    });

    test('scores a partial match proportionally', () {
      const String original = 'He neither begets nor is born';
      const String recognized = 'he neither begets';
      expect(calculateTranslationMatchPercentage(original, recognized), 50.0);
    });

    test('returns 0.0 for an empty reference string', () {
      expect(calculateTranslationMatchPercentage('', 'something'), 0.0);
    });
  });
}
