/// Text normalization + match scoring for English translation-recitation
/// comparison — the second recitation gate after the Arabic Ayah, requiring
/// the displayed English translation to be read aloud too.
///
/// Uses the same word-frequency matching rule as arabic_utils.dart (see
/// [wordMatchFlags]), but normalization is English-appropriate: lowercased
/// (unlike Arabic, English speech-to-text output and reference text differ
/// in case), and punctuation — including the bracketed clarifying words
/// some translations use, e.g. "[All] praise..." — is stripped down to the
/// bare words a speaker would actually say.
library;

import 'word_match_utils.dart';

final RegExp _punctuation = RegExp(r'[\[\]".,!?;:\-]');
final RegExp _whitespace = RegExp(r'\s+');

/// Lowercases, strips punctuation (brackets, quotes, commas, dashes, etc.),
/// and collapses whitespace.
String normalizeEnglishText(String input) {
  final String output = input.toLowerCase().replaceAll(_punctuation, ' ');
  return output.trim().replaceAll(_whitespace, ' ');
}

List<String> _normalizedWords(String text) {
  return normalizeEnglishText(text)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
}

/// Per-word match result of [original] (reference translation text)
/// against [recognized] (raw speech-to-text output). See [wordMatchFlags]
/// for the matching rule — [calculateTranslationMatchPercentage] uses the
/// same rule, so per-word UI highlighting always agrees with the
/// aggregate score.
List<bool> matchedTranslationWordFlags(String original, String recognized) {
  return wordMatchFlags(_normalizedWords(original), _normalizedWords(recognized));
}

/// Compares [original] (reference translation text) against [recognized]
/// (raw speech-to-text output), normalizing both first, and returns a
/// match rate between 0.0 and 100.0.
double calculateTranslationMatchPercentage(String original, String recognized) {
  return percentageFromFlags(matchedTranslationWordFlags(original, recognized));
}
