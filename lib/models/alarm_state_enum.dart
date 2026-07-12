/// The atomic runtime states of an active alarm wake-up window.
enum AlarmStateEnum {
  /// Default state; no alarm is currently active.
  idle,

  /// An alarm has triggered; the Adhan audio loop is playing.
  ringing,

  /// The Adhan has been silenced so the user can read the Ayah in peace;
  /// the microphone is not active yet.
  paused,

  /// The user has engaged the microphone; speech input is being captured
  /// and validated against the current Ayah via arabic_utils.
  reciting,

  /// The Arabic Ayah cleared its threshold; the translation is now shown
  /// and must be recited aloud too, validated via translation_match_utils.
  recitingTranslation,

  /// Both the Ayah and its translation cleared their thresholds; audio has
  /// stopped and the streak has been updated.
  completed,
}
