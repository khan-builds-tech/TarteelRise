import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/quran_verses.dart';
import '../data/surah_catalog.dart';
import '../utils/ayah_selection_utils.dart';

/// One recitation session's worth of Ayah content: a single verse, chosen
/// as this alarm's wake-up challenge (see [QuranRepository.buildRandomChallenge]).
class QuranSession {
  final String arabicText;
  final String translation;

  const QuranSession({
    required this.arabicText,
    required this.translation,
  });
}

/// Loads the full 114-Surah Quran dataset (Arabic text + English
/// translation, per Ayah) from `assets/data/quran_en.json` once at app
/// launch, and serves Ayah content from that in-memory cache thereafter.
///
/// [loadFromAssets] must be awaited once during app bootstrap (see
/// `main()`, alongside `DatabaseService.init`/
/// `AlarmHardwareService.initializeHardware`) before [allSurahs] or
/// [buildRandomChallenge] are used — both are plain synchronous reads
/// afterwards, with no per-call asset access.
class QuranRepository {
  static const String _assetPath = 'assets/data/quran_en.json';

  /// A challenge verse is only ever picked from ayahs at or under this
  /// word count — short enough to recite right after waking up.
  static const int maxChallengeAyahWords = 10;

  final Random _random;

  List<Surah> _surahs = const <Surah>[];
  Map<int, List<AyahRecord>> _versesBySurahId = const <int, List<AyahRecord>>{};

  /// [random] is injectable so tests can seed it for deterministic
  /// challenge-verse selection; production code should just use the
  /// default.
  QuranRepository({Random? random}) : _random = random ?? Random();

  /// All 114 Surahs, in Quran order, once [loadFromAssets] has completed.
  /// Empty until then (or if it failed).
  List<Surah> get allSurahs => _surahs;

  bool get isLoaded => _surahs.isNotEmpty;

  /// Parses the bundled dataset asynchronously: `rootBundle.loadString`
  /// reads the ~2.3MB asset off the synchronous call stack, and the
  /// `jsonDecode`/model-inflation below runs after that `await`, so this
  /// never blocks the UI thread — it's meant to be awaited once during
  /// app bootstrap, before `runApp()`, exactly like the Hive/hardware
  /// initialization it sits alongside in `main()`.
  ///
  /// Fails safe: a missing/corrupt asset is caught and logged rather than
  /// thrown, leaving [allSurahs] empty and [buildRandomChallenge] falling
  /// back to its own safe default — a data problem must never crash the
  /// alarm flow the way a real hardware fault mustn't either.
  Future<void> loadFromAssets() async {
    try {
      final String raw = await rootBundle.loadString(_assetPath);
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;

      final List<Surah> surahs = <Surah>[];
      final Map<int, List<AyahRecord>> versesBySurahId = <int, List<AyahRecord>>{};

      for (final dynamic entry in decoded) {
        final Map<String, dynamic> surahJson = entry as Map<String, dynamic>;
        final Surah surah = Surah.fromJson(surahJson);
        surahs.add(surah);

        final List<dynamic> versesJson = surahJson['verses'] as List<dynamic>;
        versesBySurahId[surah.id] = versesJson
            .map((dynamic v) => AyahRecord.fromJson(v as Map<String, dynamic>))
            .toList();
      }

      _surahs = List<Surah>.unmodifiable(surahs);
      _versesBySurahId = Map<int, List<AyahRecord>>.unmodifiable(versesBySurahId);
    } catch (error, stackTrace) {
      debugPrint('QuranRepository.loadFromAssets failed: $error\n$stackTrace');
    }
  }

  /// The cached [Surah] metadata for [id], or `null` if [loadFromAssets]
  /// hasn't completed or [id] doesn't exist.
  Surah? surahById(int id) {
    for (final Surah surah in _surahs) {
      if (surah.id == id) return surah;
    }
    return null;
  }

  /// Whether real, loaded verse text exists for Surah [surahId] — true for
  /// every id 1-114 once [loadFromAssets] has completed successfully.
  bool hasVerseData(int surahId) => _versesBySurahId[surahId]?.isNotEmpty ?? false;

  /// The Ayah records for Surah [surahId], or an empty list if
  /// [loadFromAssets] hasn't completed or [surahId] doesn't exist.
  List<AyahRecord> versesFor(int surahId) =>
      _versesBySurahId[surahId] ?? const <AyahRecord>[];

  /// Picks a single random Ayah from Surah [surahIndex] to be this alarm's
  /// wake-up challenge verse — via rejection sampling, re-rolling until
  /// one is found at or under [maxChallengeAyahWords] words (see
  /// [pickRandomIndexWithinWordLimit]), so the user is never handed a long
  /// passage to recite straight out of bed.
  ///
  /// Falls back to Al-Fatiha (Surah 1) if [surahIndex] has no verse data —
  /// only reachable if [loadFromAssets] hasn't run yet or the asset failed
  /// to parse, since every Surah 1-114 is otherwise covered. Showing an
  /// empty Ayah card would leave the user with nothing to recite and no
  /// way to dismiss the alarm, which is worse than a real, complete Surah.
  QuranSession buildRandomChallenge({required int surahIndex}) {
    final Surah? surah = surahById(surahIndex);
    final List<AyahRecord> verses = versesFor(surahIndex);

    if (surah == null || verses.isEmpty) {
      debugPrint(
        'QuranRepository: no verse data available for Surah $surahIndex '
        '(has loadFromAssets completed?) — falling back to Al-Fatiha.',
      );
      if (surahIndex != 1) {
        return buildRandomChallenge(surahIndex: 1);
      }
      // Even Al-Fatiha isn't loaded — the asset itself failed. Nothing
      // safe to show; empty text at least can't crash the ringing flow.
      return const QuranSession(arabicText: '', translation: '');
    }

    final List<int> wordCounts = verses.map((verse) => wordCount(verse.text)).toList();
    final int index = pickRandomIndexWithinWordLimit(
      wordCounts: wordCounts,
      maxWords: maxChallengeAyahWords,
      random: _random,
    );
    final AyahRecord chosen = verses[index];

    return QuranSession(arabicText: chosen.text, translation: chosen.translation);
  }
}
