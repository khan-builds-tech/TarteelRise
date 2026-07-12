/// Text normalization + match scoring for Arabic recitation comparison.
///
/// Speech-to-text output must be compared against reference Ayah text
/// leniently — raspy morning voices and minor diacritic drift should not
/// cause false-negative rejections.
library;

import 'word_match_utils.dart';

final RegExp _diacritics = RegExp(r'[ً-ْ]');
final RegExp _alefVariants = RegExp(r'[إأآ]');
final RegExp _whitespace = RegExp(r'\s+');

/// Strips Tashkeel diacritics, folds Alef variants to a bare Alef, and
/// collapses whitespace so two recitations of the same Ayah normalize to
/// the same comparison string regardless of vocalization marks.
String normalizeArabicText(String input) {
  String output = input.replaceAll(_diacritics, '');
  output = output.replaceAll(_alefVariants, 'ا');
  return output.trim().replaceAll(_whitespace, ' ');
}

List<String> _normalizedWords(String text) {
  return normalizeArabicText(text)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
}

/// Per-word match result of [original] (reference Ayah text) against
/// [recognized] (raw speech-to-text output): one flag per word of
/// [original], in order, `true` if that word was found among
/// [recognized]'s words. See [wordMatchFlags] for the matching rule this
/// is built on — [calculateMatchPercentage] uses the same rule, so
/// per-word UI highlighting always agrees with the aggregate score.
List<bool> matchedWordFlags(String original, String recognized) {
  return wordMatchFlags(_normalizedWords(original), _normalizedWords(recognized));
}

/// Compares [original] (reference Ayah text) against [recognized] (raw
/// speech-to-text output), normalizing both first, and returns a match
/// rate between 0.0 and 100.0.
double calculateMatchPercentage(String original, String recognized) {
  return percentageFromFlags(matchedWordFlags(original, recognized));
}
