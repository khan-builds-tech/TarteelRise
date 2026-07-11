/// The atomic runtime states of an active alarm wake-up window.
enum AlarmStateEnum {
  /// Default state; no alarm is currently active.
  idle,

  /// An alarm has triggered; the Adhan audio loop is playing.
  ringing,

  /// The user has engaged the microphone; speech input is being captured
  /// and validated against the current Ayah via arabic_utils.
  reciting,

  /// The match percentage cleared the configured threshold; audio has
  /// stopped, the translation is revealed, and the streak has been updated.
  completed,
}
