/// A single Surah's catalog metadata, matching one entry of the bundled
/// `assets/data/quran_en.json` dataset (minus its `verses`, which
/// `QuranRepository` caches separately as `AyahRecord`s).
class Surah {
  final int id;

  /// Arabic script, e.g. `'الفاتحة'`.
  final String name;

  /// English phonetic name, e.g. `'Al-Fatihah'`.
  final String transliteration;

  /// English meaning of the name, e.g. `'The Opener'`.
  final String translation;

  final int totalVerses;

  const Surah({
    required this.id,
    required this.name,
    required this.transliteration,
    required this.translation,
    required this.totalVerses,
  });

  factory Surah.fromJson(Map<String, dynamic> json) {
    return Surah(
      id: json['id'] as int,
      name: json['name'] as String,
      transliteration: json['transliteration'] as String,
      translation: json['translation'] as String,
      totalVerses: json['total_verses'] as int,
    );
  }
}
