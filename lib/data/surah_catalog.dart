/// A single Surah's catalog metadata — just enough for a selection UI.
/// Ayah *text*/translation come from the Quran verse database described in
/// the product spec (Section 4: local SQLite/JSON Quran data), which
/// hasn't been built yet.
class Surah {
  final int index;
  final String arabicName;
  final String englishName;
  final int ayahCount;

  const Surah({
    required this.index,
    required this.arabicName,
    required this.englishName,
    required this.ayahCount,
  });
}

/// Starter catalog covering the Quran's most commonly recited Surahs —
/// deliberately NOT the full 114. Hand-entering all 114 names/ayah counts
/// from memory risks factual errors in religious content; this list is
/// limited to entries verified for accuracy. Extend it once the real Quran
/// verse database is built, ideally sourced from a verified dataset rather
/// than hand-entered.
const List<Surah> starterSurahCatalog = <Surah>[
  Surah(index: 1, arabicName: 'الفاتحة', englishName: 'Al-Fatiha', ayahCount: 7),
  Surah(index: 2, arabicName: 'البقرة', englishName: 'Al-Baqarah', ayahCount: 286),
  Surah(index: 3, arabicName: 'آل عمران', englishName: 'Aal-E-Imran', ayahCount: 200),
  Surah(index: 4, arabicName: 'النساء', englishName: 'An-Nisa', ayahCount: 176),
  Surah(index: 5, arabicName: 'المائدة', englishName: "Al-Ma'idah", ayahCount: 120),
  Surah(index: 12, arabicName: 'يوسف', englishName: 'Yusuf', ayahCount: 111),
  Surah(index: 18, arabicName: 'الكهف', englishName: 'Al-Kahf', ayahCount: 110),
  Surah(index: 19, arabicName: 'مريم', englishName: 'Maryam', ayahCount: 98),
  Surah(index: 36, arabicName: 'يس', englishName: 'Ya-Sin', ayahCount: 83),
  Surah(index: 55, arabicName: 'الرحمن', englishName: 'Ar-Rahman', ayahCount: 78),
  Surah(index: 56, arabicName: 'الواقعة', englishName: "Al-Waqi'ah", ayahCount: 96),
  Surah(index: 67, arabicName: 'الملك', englishName: 'Al-Mulk', ayahCount: 30),
  Surah(index: 112, arabicName: 'الإخلاص', englishName: 'Al-Ikhlas', ayahCount: 4),
  Surah(index: 113, arabicName: 'الفلق', englishName: 'Al-Falaq', ayahCount: 5),
  Surah(index: 114, arabicName: 'الناس', englishName: 'An-Nas', ayahCount: 6),
];
