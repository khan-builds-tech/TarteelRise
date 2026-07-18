/// Word-frequency (multiset) matching shared by Arabic recitation scoring
/// (arabic_utils.dart) and English translation-recitation scoring
/// (translation_match_utils.dart). Normalization is language-specific and
/// lives in those files; this is just the comparison algorithm.
library;

/// Per-word match result of [originalWords] against [recognizedWords]: one
/// flag per word of [originalWords], in order, `true` if that word was
/// found among [recognizedWords].
///
/// Matching is word-frequency based, not positional: each word in
/// [originalWords] is checked off against the multiset of
/// [recognizedWords], so reordering or a single dropped word only flips
/// that one word's flag instead of misaligning everything after it.
List<bool> wordMatchFlags(List<String> originalWords, List<String> recognizedWords) {
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

/// OR-merges [previous] and [current] word-match flags position by
/// position: once a word has been recognized, it stays recognized even if
/// a later speech-to-text partial result revises its whole-utterance
/// hypothesis and drops that word. Returns [current] unchanged if
/// [previous] is a different length (the very first result of an
/// attempt, where there is nothing yet to merge with).
///
/// This is the actual ratchet — callers should keep accumulating into one
/// running flags list with this, then derive the displayed percentage
/// from that *same* list via [percentageFromFlags], rather than tracking
/// the percentage separately. Deriving both from one shared list is what
/// guarantees the highlighted word count and the displayed percentage
/// always agree; ratcheting the percentage alone while highlighting still
/// reflects only the latest raw chunk is what lets them drift apart.
List<bool> mergeWordMatchFlags(List<bool> previous, List<bool> current) {
  if (previous.length != current.length) {
    return current;
  }

  return List<bool>.generate(
    current.length,
    (int i) => previous[i] || current[i],
  );
}

/// The percentage of `true` flags in [flags], 0.0 for an empty list rather
/// than dividing by zero.
double percentageFromFlags(List<bool> flags) {
  if (flags.isEmpty) {
    return 0.0;
  }

  final int matchedCount = flags.where((matched) => matched).length;
  final double percentage = (matchedCount / flags.length) * 100.0;
  return percentage.clamp(0.0, 100.0);
}
