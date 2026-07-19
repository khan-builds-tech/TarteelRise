import 'dart:math';

/// Word count of [text], splitting on whitespace — the same simple
/// tokenization the speech-matching utils use elsewhere. Empty/blank text
/// counts as zero words rather than one.
int wordCount(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// Picks a random index into [wordCounts] — one entry per candidate ayah —
/// whose value is at most [maxWords], via rejection sampling: rolls a new
/// random index (using [random], so callers can inject a seeded instance
/// for deterministic tests) up to [maxAttempts] times until one qualifies.
///
/// Falls back to the index of the single shortest candidate if none
/// qualifies within [maxAttempts] rolls — e.g. a Surah where every ayah
/// happens to exceed [maxWords] — so this can never spin forever or
/// return nothing to recite.
int pickRandomIndexWithinWordLimit({
  required List<int> wordCounts,
  required int maxWords,
  required Random random,
  int maxAttempts = 50,
}) {
  if (wordCounts.isEmpty) {
    throw ArgumentError.value(wordCounts, 'wordCounts', 'must not be empty');
  }

  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    final int candidate = random.nextInt(wordCounts.length);
    if (wordCounts[candidate] <= maxWords) {
      return candidate;
    }
  }

  int shortestIndex = 0;
  for (int i = 1; i < wordCounts.length; i++) {
    if (wordCounts[i] < wordCounts[shortestIndex]) {
      shortestIndex = i;
    }
  }
  return shortestIndex;
}
