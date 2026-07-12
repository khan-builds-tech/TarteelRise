/// Text normalization + match scoring for Arabic recitation comparison.
///
/// Speech-to-text output must be compared against reference Ayah text
/// leniently — raspy morning voices and minor diacritic drift should not
/// cause false-negative rejections.
library;

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
/// [recognized]'s words.
///
/// Matching is word-frequency based, not positional: each word in
/// [original] is checked off against the multiset of words in
/// [recognized], so reordering or a single dropped word only flips that
/// one word's flag instead of misaligning everything after it. This is
/// the same rule [calculateMatchPercentage] uses — it's built on top of
/// this function — so per-word UI highlighting always agrees with the
/// aggregate score.
List<bool> matchedWordFlags(String original, String recognized) {
  final List<String> originalWords = _normalizedWords(original);
  final List<String> recognizedWords = _normalizedWords(recognized);

  final Map<String, int> recognizedCounts = <String, int>{};
  for (final String word in recognizedWords) {
    recognizedCounts[word] = (recognizedCounts[word] ?? 0) + 1;
  }

  return originalWords.map((word) {
    final int remaining = recognizedCounts[word] ?? 0;
    if (remaining > 0) {
      recognizedCounts[word] = remaining - 1;
      return true;
    }
    return false;
  }).toList();
}

/// Compares [original] (reference Ayah text) against [recognized] (raw
/// speech-to-text output), normalizing both first, and returns a match
/// rate between 0.0 and 100.0.
double calculateMatchPercentage(String original, String recognized) {
  final List<bool> flags = matchedWordFlags(original, recognized);
  if (flags.isEmpty) {
    return 0.0;
  }

  final int matchedCount = flags.where((matched) => matched).length;
  final double percentage = (matchedCount / flags.length) * 100.0;
  return percentage.clamp(0.0, 100.0);
}
