/// One Ayah's Arabic text + English translation.
class AyahRecord {
  final int ayahNumber;
  final String arabicText;
  final String translation;

  const AyahRecord({
    required this.ayahNumber,
    required this.arabicText,
    required this.translation,
  });
}

/// Real verse text, seeded ONLY for Surahs short and universally recited
/// enough that the text can be verified from memory with confidence —
/// Al-Fatiha (recited in every prayer) and the last three Surahs (Al-Ikhlas,
/// Al-Falaq, An-Nas — "Al-Mu'awwidhat", among the most memorized in the
/// Quran). Every other Surah in [starterSurahCatalog] has metadata
/// (name, ayah count) but no verse text yet — hand-transcribing full long
/// Surahs (286 ayahs for Al-Baqarah, etc.) from memory risks real errors in
/// religious text. [QuranRepository] falls back to Al-Fatiha for any Surah
/// without an entry here; extend this from a verified source (e.g. an
/// official Quran text API/dataset) before shipping the rest.
final Map<int, List<AyahRecord>> quranVerses = <int, List<AyahRecord>>{
  1: <AyahRecord>[
    const AyahRecord(
      ayahNumber: 1,
      arabicText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
      translation: 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
    ),
    const AyahRecord(
      ayahNumber: 2,
      arabicText: 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      translation: '[All] praise is [due] to Allah, Lord of the worlds -',
    ),
    const AyahRecord(
      ayahNumber: 3,
      arabicText: 'الرَّحْمَٰنِ الرَّحِيمِ',
      translation: 'The Entirely Merciful, the Especially Merciful,',
    ),
    const AyahRecord(
      ayahNumber: 4,
      arabicText: 'مَالِكِ يَوْمِ الدِّينِ',
      translation: 'Sovereign of the Day of Recompense.',
    ),
    const AyahRecord(
      ayahNumber: 5,
      arabicText: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
      translation: 'It is You we worship and You we ask for help.',
    ),
    const AyahRecord(
      ayahNumber: 6,
      arabicText: 'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ',
      translation: 'Guide us to the straight path -',
    ),
    const AyahRecord(
      ayahNumber: 7,
      arabicText:
          'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ',
      translation:
          'The path of those upon whom You have bestowed favor, not of those who have '
          'evoked [Your] anger or of those who are astray.',
    ),
  ],
  112: <AyahRecord>[
    const AyahRecord(
      ayahNumber: 1,
      arabicText: 'قُلْ هُوَ اللَّهُ أَحَدٌ',
      translation: 'Say, "He is Allah, [who is] One,',
    ),
    const AyahRecord(
      ayahNumber: 2,
      arabicText: 'اللَّهُ الصَّمَدُ',
      translation: 'Allah, the Eternal Refuge.',
    ),
    const AyahRecord(
      ayahNumber: 3,
      arabicText: 'لَمْ يَلِدْ وَلَمْ يُولَدْ',
      translation: 'He neither begets nor is born,',
    ),
    const AyahRecord(
      ayahNumber: 4,
      arabicText: 'وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ',
      translation: 'Nor is there to Him any equivalent."',
    ),
  ],
  113: <AyahRecord>[
    const AyahRecord(
      ayahNumber: 1,
      arabicText: 'قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ',
      translation: 'Say, "I seek refuge in the Lord of daybreak',
    ),
    const AyahRecord(
      ayahNumber: 2,
      arabicText: 'مِنْ شَرِّ مَا خَلَقَ',
      translation: 'From the evil of that which He created',
    ),
    const AyahRecord(
      ayahNumber: 3,
      arabicText: 'وَمِنْ شَرِّ غَاسِقٍ إِذَا وَقَبَ',
      translation: 'And from the evil of darkness when it settles',
    ),
    const AyahRecord(
      ayahNumber: 4,
      arabicText: 'وَمِنْ شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ',
      translation: 'And from the evil of the blowers in knots [i.e., malignant witchcraft]',
    ),
    const AyahRecord(
      ayahNumber: 5,
      arabicText: 'وَمِنْ شَرِّ حَاسِدٍ إِذَا حَسَدَ',
      translation: 'And from the evil of an envier when he envies."',
    ),
  ],
  114: <AyahRecord>[
    const AyahRecord(
      ayahNumber: 1,
      arabicText: 'قُلْ أَعُوذُ بِرَبِّ النَّاسِ',
      translation: 'Say, "I seek refuge in the Lord of mankind,',
    ),
    const AyahRecord(
      ayahNumber: 2,
      arabicText: 'مَلِكِ النَّاسِ',
      translation: 'The Sovereign of mankind,',
    ),
    const AyahRecord(
      ayahNumber: 3,
      arabicText: 'إِلَٰهِ النَّاسِ',
      translation: 'The God of mankind,',
    ),
    const AyahRecord(
      ayahNumber: 4,
      arabicText: 'مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ',
      translation: 'From the evil of the whisperer who withdraws [after his whisper],',
    ),
    const AyahRecord(
      ayahNumber: 5,
      arabicText: 'الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ',
      translation: 'Who whispers [evil] into the breasts of mankind,',
    ),
    const AyahRecord(
      ayahNumber: 6,
      arabicText: 'مِنَ الْجِنَّةِ وَالنَّاسِ',
      translation: 'From among the jinn and mankind."',
    ),
  ],
};
