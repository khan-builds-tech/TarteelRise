import 'alarm_model.dart';

/// In-memory workspace for a single wake-up call. Lives only for the
/// duration of the ringing/reciting/completed window and is discarded on
/// `resetToIdle` — it is never persisted to Hive.
class ActiveAlarmSession {
  final AlarmModel activeAlarm;
  final String currentAyahArabic;
  final String currentAyahTranslation;
  final double currentProgress;

  /// One flag per word of [currentAyahArabic] (in order): whether that
  /// word has been recognized so far, per [matchedWordFlags]. Empty until
  /// the first speech result arrives.
  final List<bool> matchedWordFlags;

  /// True if this session reached `completed` via the Emergency Snooze
  /// typed-translation fallback rather than a validated recitation — the
  /// UI uses this to show that the streak was broken, not extended.
  final bool completedViaEmergencyFallback;

  const ActiveAlarmSession({
    required this.activeAlarm,
    required this.currentAyahArabic,
    required this.currentAyahTranslation,
    this.currentProgress = 0.0,
    this.matchedWordFlags = const <bool>[],
    this.completedViaEmergencyFallback = false,
  });

  ActiveAlarmSession copyWith({
    double? currentProgress,
    List<bool>? matchedWordFlags,
    bool? completedViaEmergencyFallback,
  }) {
    return ActiveAlarmSession(
      activeAlarm: activeAlarm,
      currentAyahArabic: currentAyahArabic,
      currentAyahTranslation: currentAyahTranslation,
      currentProgress: currentProgress ?? this.currentProgress,
      matchedWordFlags: matchedWordFlags ?? this.matchedWordFlags,
      completedViaEmergencyFallback:
          completedViaEmergencyFallback ?? this.completedViaEmergencyFallback,
    );
  }
}
