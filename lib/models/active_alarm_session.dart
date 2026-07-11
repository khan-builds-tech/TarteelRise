import 'alarm_model.dart';

/// In-memory workspace for a single wake-up call. Lives only for the
/// duration of the ringing/reciting/completed window and is discarded on
/// `resetToIdle` — it is never persisted to Hive.
class ActiveAlarmSession {
  final AlarmModel activeAlarm;
  final String currentAyahArabic;
  final String currentAyahTranslation;
  final double currentProgress;

  const ActiveAlarmSession({
    required this.activeAlarm,
    required this.currentAyahArabic,
    required this.currentAyahTranslation,
    this.currentProgress = 0.0,
  });

  ActiveAlarmSession copyWith({double? currentProgress}) {
    return ActiveAlarmSession(
      activeAlarm: activeAlarm,
      currentAyahArabic: currentAyahArabic,
      currentAyahTranslation: currentAyahTranslation,
      currentProgress: currentProgress ?? this.currentProgress,
    );
  }
}
