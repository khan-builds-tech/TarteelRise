/// Word-frequency (multiset) matching shared by Arabic recitation scoring
/// (arabic_utils.dart) and English translation-recitation scoring
/// (translation_match_utils.dart). Normalization is language-specific and
/// lives in those files; this is just the comparison algorithm.
library;

/// Classic O(n*m) edit-distance DP: the minimum number of single-character
/// insertions/deletions/substitutions to turn [a] into [b]. Only ever
/// called on individual recited words (a handful of characters each,
/// [ayah_selection_utils.dart]'s `maxChallengeAyahWords` caps a whole Ayah
/// at 10 words), so the quadratic cost is irrelevant in practice.
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> previousRow = List<int>.generate(b.length + 1, (int i) => i);
  List<int> currentRow = List<int>.filled(b.length + 1, 0);

  for (int i = 1; i <= a.length; i++) {
    currentRow[0] = i;
    for (int j = 1; j <= b.length; j++) {
      final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final int deletion = previousRow[j] + 1;
      final int insertion = currentRow[j - 1] + 1;
      final int substitution = previousRow[j - 1] + cost;
      currentRow[j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
    }
    final List<int> swap = previousRow;
    previousRow = currentRow;
    currentRow = swap;
  }

  return previousRow[b.length];
}

/// Whether [recognizedWord] is close enough to [targetWord] to count as the
/// same recited word, tolerating a slightly misheard speech-to-text
/// transcription rather than requiring a character-for-character match.
///
/// Words of 2 characters or fewer require an exact match: Arabic and
/// English both have plenty of short, distinct words a single edit apart
/// (e.g. "من"/"لن", "in"/"on") — fuzzy-matching those would let a genuinely
/// wrong word silently pass instead of catching a real mishearing. Longer
/// words tolerate 1 edit (4 characters or fewer) or 2 edits (5+), which
/// covers a dropped/added vowel or a single substituted letter without
/// being loose enough to conflate two different words.
bool isFuzzyWordMatch(String targetWord, String recognizedWord) {
  if (targetWord == recognizedWord) return true;

  final int shorterLength =
      targetWord.length < recognizedWord.length ? targetWord.length : recognizedWord.length;
  if (shorterLength <= 2) return false;

  final int maxEdits = shorterLength <= 4 ? 1 : 2;
  return levenshteinDistance(targetWord, recognizedWord) <= maxEdits;
}

/// Per-word match result of [originalWords] against [recognizedWords]: one
/// flag per word of [originalWords], in order, `true` if that word was
/// found among [recognizedWords] — exactly, or a close enough fuzzy match
/// per [isFuzzyWordMatch] to plausibly be the same word slightly misheard
/// by speech-to-text.
///
/// Matching is word-frequency based, not positional: each word in
/// [originalWords] is checked off against the multiset of
/// [recognizedWords], so reordering or a single dropped word only flips
/// that one word's flag instead of misaligning everything after it. Exact
/// matches are always preferred over fuzzy ones (checked first, and
/// consumed from the multiset first) so an exact match is never "stolen"
/// by a fuzzy match against a different original word.
List<bool> wordMatchFlags(List<String> originalWords, List<String> recognizedWords) {
  final List<String> remaining = List<String>.from(recognizedWords);

  return originalWords.map((word) {
    final int exactIndex = remaining.indexOf(word);
    if (exactIndex != -1) {
      remaining.removeAt(exactIndex);
      return true;
    }

    final int fuzzyIndex =
        remaining.indexWhere((candidate) => isFuzzyWordMatch(word, candidate));
    if (fuzzyIndex != -1) {
      remaining.removeAt(fuzzyIndex);
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
