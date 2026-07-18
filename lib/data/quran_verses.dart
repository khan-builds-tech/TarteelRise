/// One Ayah's vocalized Arabic text + English translation, matching one
/// entry of a Surah's `verses` array in the bundled
/// `assets/data/quran_en.json` dataset.
class AyahRecord {
  /// The verse number within its Surah (1-based).
  final int id;

  /// Vocalized Arabic text, used for speech-recognition matching.
  final String text;

  /// English translation, shown underneath the Arabic for UX clarity and
  /// used for the translation-recitation gate.
  final String translation;

  const AyahRecord({
    required this.id,
    required this.text,
    required this.translation,
  });

  factory AyahRecord.fromJson(Map<String, dynamic> json) {
    return AyahRecord(
      id: json['id'] as int,
      text: json['text'] as String,
      translation: json['translation'] as String,
    );
  }
}
