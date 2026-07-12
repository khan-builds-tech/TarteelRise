/// Pure Smart-Bookmarking logic (spec Section 4), isolated from storage so
/// it's directly testable: which ayahs a session should cover, and where
/// to resume from next time.
library;

/// The ayah numbers (1-indexed, inclusive) to recite this session, starting
/// at [startAyah]. Clamped so a session never reads past the end of the
/// Surah — a request near the end of a Surah returns fewer ayahs than
/// [requestedCount] rather than spilling into the next Surah.
List<int> ayahNumbersForSession({
  required int startAyah,
  required int requestedCount,
  required int totalAyahsInSurah,
}) {
  final int lastAyah =
      (startAyah + requestedCount - 1).clamp(startAyah, totalAyahsInSurah);
  return <int>[for (int ayah = startAyah; ayah <= lastAyah; ayah++) ayah];
}

/// The ayah to resume from next time: continues right after [lastAyahRead],
/// wrapping back to 1 once the Surah is exhausted — so a Surah is recited
/// on a continuous loop across mornings rather than dead-ending.
int computeNextBookmark({
  required int lastAyahRead,
  required int totalAyahsInSurah,
}) {
  return lastAyahRead >= totalAyahsInSurah ? 1 : lastAyahRead + 1;
}
