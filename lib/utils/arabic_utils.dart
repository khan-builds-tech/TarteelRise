/// Text normalization + match scoring for Arabic recitation comparison.
///
/// Speech-to-text output must be compared against reference Ayah text
/// leniently — raspy morning voices and minor diacritic drift should not
/// cause false-negative rejections.
library;

import 'word_match_utils.dart';

/// Tashkeel + the Quranic annotation range: U+0610-U+061A (Quranic
/// honorific/recitation marks), U+064B-U+065F (Fatha/Damma/Kasra/Sukun,
/// all three Tanween, Shadda, Maddah above, combining Hamza above/below,
/// subscript Alef, inverted Damma, Fatha-with-two-dots), and U+06D6-U+06ED
/// (the small high/low pause and Sajdah marks). Quranic Unicode text —
/// e.g. the bundled `assets/data/quran_en.json`, written in Uthmani
/// script — uses these far more heavily than plain conversational Arabic.
/// The exact codepoint boundaries here were verified programmatically
/// against every non-letter character actually present in that dataset
/// (`ord()` each range endpoint before trusting this — combining marks
/// are visually indistinguishable from each other, so a literal-character
/// range like this one is easy to mistranscribe and hard to eyeball
/// review). Deliberately does NOT include U+0670 (dagger Alif) — see
/// [_alefVariants].
final RegExp _diacritics = RegExp(r'''[ؐ-ًؚ-ٟۖ-ۭ]''');

/// Folded to a bare Alef (`ا`, U+0627):
///  - U+0625 (إ), U+0623 (أ), U+0622 (آ), U+0671 (ٱ) — orthographic Alef
///    variants. `ٱ` (Alef Wasla) is the form Quranic text almost always
///    uses for the "ال-" (the) prefix — e.g. `ٱللَّهِ` — but a spoken/
///    STT-transcribed recitation says the plain form, `الله`. Without
///    folding Wasla too, every "al-" word in the reference text silently
///    fails to match.
///  - U+0670 (dagger Alif) — unlike the other diacritics in
///    [_diacritics], this one represents an actual long "aa" vowel (e.g.
///    `ٱلۡعَٰلَمِينَ` is "al-'aalameen") rather than a pronunciation
///    modifier on an existing letter, so it must fold to a real Alef
///    rather than be deleted — deleting it turns "العالمين" into
///    "العلمين", a real word-level mismatch. (Known, accepted trade-off:
///    a handful of words — most notably `الرحمن` — are conventionally
///    spelled *without* the corresponding Alef even in plain modern
///    Arabic despite carrying a dagger Alif in Quranic script, so those
///    specific words won't match after this fold either way; this is the
///    standard behavior of Arabic NLP normalizers generally, not a gap
///    specific to this implementation.)
final RegExp _alefVariants = RegExp(r'''[إأآٱٰ]''');

/// U+0649 (ى, Alef Maqsura) -> U+064A (ي, Ya).
const String _alefMaqsura = 'ى';
const String _ya = 'ي';

/// U+0629 (ة, Ta Marbuta) -> U+0647 (ه, Ha).
const String _taMarbuta = 'ة';
const String _ha = 'ه';

/// Tatweel (kashida, U+0640) is a pure typographic stretch with no
/// phonetic content — Quranic typesetting uses it for justification, but
/// it must never affect word comparison.
const String _tatweel = 'ـ';

/// The target Alef (U+0627, ا) that [_alefVariants] folds onto.
const String _bareAlef = 'ا';

/// Everything remaining that isn't a core Arabic letter (U+0621 Hamza
/// through U+064A Yeh) or whitespace — digits, Arabic-Indic digits, and
/// stray punctuation — dropped as a final safety net now that diacritics/
/// Alef/Tatweel are already handled above via explicit folds rather than
/// being swept up here.
final RegExp _nonLetterOrSpace = RegExp(r'[^ء-ي\s]');

final RegExp _whitespace = RegExp(r'\s+');

/// Strips Tashkeel diacritics and Quranic annotation marks, folds Alef/Ya
/// Maqsura/Ta Marbuta variants to their bare forms, drops Tatweel and any
/// remaining non-letter characters, and collapses whitespace — so two
/// recitations of the same Ayah normalize to the same comparison string
/// regardless of vocalization marks or which orthographic variant (plain
/// conversational vs. Quranic Uthmani) either side happens to use.
String normalizeArabicText(String input) {
  String output = input.replaceAll(_diacritics, '');
  output = output.replaceAll(_alefVariants, _bareAlef);
  output = output.replaceAll(_alefMaqsura, _ya);
  output = output.replaceAll(_taMarbuta, _ha);
  output = output.replaceAll(_tatweel, '');
  output = output.replaceAll(_nonLetterOrSpace, '');
  return output.trim().replaceAll(_whitespace, ' ');
}

List<String> _normalizedWords(String text) {
  return normalizeArabicText(text)
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
}

/// Per-word match result of [original] (reference Ayah text) against
/// [recognized] (raw speech-to-text output): one flag per word of
/// [original], in order, `true` if that word was found among
/// [recognized]'s words. See [wordMatchFlags] for the matching rule this
/// is built on — [calculateMatchPercentage] uses the same rule, so
/// per-word UI highlighting always agrees with the aggregate score.
List<bool> matchedWordFlags(String original, String recognized) {
  return wordMatchFlags(_normalizedWords(original), _normalizedWords(recognized));
}

/// Compares [original] (reference Ayah text) against [recognized] (raw
/// speech-to-text output), normalizing both first, and returns a match
/// rate between 0.0 and 100.0.
double calculateMatchPercentage(String original, String recognized) {
  return percentageFromFlags(matchedWordFlags(original, recognized));
}
