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

/// Compares [original] (reference Ayah text) against [recognized] (raw
/// speech-to-text output), normalizing both first, and returns a match
/// rate between 0.0 and 100.0.
///
/// Scoring is word-frequency based rather than strict order/equality: each
/// word in [original] is matched against the multiset of words in
/// [recognized], so reordering or a single dropped word only partially
/// lowers the score instead of failing the whole comparison outright.
double calculateMatchPercentage(String original, String recognized) {
  final List<String> originalWords = normalizeArabicText(original)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();

  if (originalWords.isEmpty) {
    return 0.0;
  }

  final List<String> recognizedWords = normalizeArabicText(recognized)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();

  final Map<String, int> recognizedCounts = <String, int>{};
  for (final String word in recognizedWords) {
    recognizedCounts[word] = (recognizedCounts[word] ?? 0) + 1;
  }

  int matchedCount = 0;
  for (final String word in originalWords) {
    final int remaining = recognizedCounts[word] ?? 0;
    if (remaining > 0) {
      matchedCount++;
      recognizedCounts[word] = remaining - 1;
    }
  }

  final double percentage = (matchedCount / originalWords.length) * 100.0;
  return percentage.clamp(0.0, 100.0);
}
