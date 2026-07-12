import 'package:flutter/foundation.dart';

import '../data/quran_verses.dart';
import '../data/surah_catalog.dart';
import '../utils/bookmark_utils.dart';

/// One recitation session's worth of Ayah content, plus where the Surah's
/// bookmark should move to for next time.
class QuranSession {
  final String arabicText;
  final String translation;
  final int nextBookmarkAyah;

  const QuranSession({
    required this.arabicText,
    required this.translation,
    required this.nextBookmarkAyah,
  });
}

/// Looks up Ayah content for a recitation session and computes Smart
/// Bookmarking progression (spec Section 4): resume where the last session
/// left off, wrapping back to the start once a Surah is exhausted.
class QuranRepository {
  const QuranRepository();

  /// Whether real verse text exists for [surahIndex] yet — see
  /// `quran_verses.dart` for which Surahs are seeded and why.
  bool hasVerseData(int surahIndex) => quranVerses.containsKey(surahIndex);

  /// Builds the session for [surahIndex], reciting up to
  /// [requestedAyahCount] ayahs starting at [startAyah].
  ///
  /// Falls back to Al-Fatiha (Surah 1, which is fully seeded) if
  /// [surahIndex] has no verse text yet — showing an empty Ayah card would
  /// leave the user with nothing to recite, which is worse than falling
  /// back to a real, complete Surah.
  QuranSession buildSession({
    required int surahIndex,
    required int startAyah,
    required int requestedAyahCount,
  }) {
    if (!hasVerseData(surahIndex)) {
      debugPrint(
        'QuranRepository: no verse text for Surah $surahIndex yet, falling back to Al-Fatiha.',
      );
      return buildSession(surahIndex: 1, startAyah: 1, requestedAyahCount: requestedAyahCount);
    }

    final Surah surah = starterSurahCatalog.firstWhere((s) => s.index == surahIndex);
    final List<AyahRecord> verses = quranVerses[surahIndex]!;

    final List<int> ayahNumbers = ayahNumbersForSession(
      startAyah: startAyah.clamp(1, surah.ayahCount),
      requestedCount: requestedAyahCount,
      totalAyahsInSurah: surah.ayahCount,
    );

    final List<AyahRecord> selected = ayahNumbers
        .map((number) => verses.firstWhere((verse) => verse.ayahNumber == number))
        .toList();

    return QuranSession(
      arabicText: selected.map((verse) => verse.arabicText).join(' '),
      translation: selected.map((verse) => verse.translation).join(' '),
      nextBookmarkAyah: computeNextBookmark(
        lastAyahRead: ayahNumbers.last,
        totalAyahsInSurah: surah.ayahCount,
      ),
    );
  }
}
