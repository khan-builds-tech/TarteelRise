import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';

import '../models/alarm_model.dart';
import '../providers/alarm_state_provider.dart';
import 'alarm_hardware_service.dart';
import 'database_service.dart';

/// The Ayah text pairing that should be shown when [alarm] starts ringing.
class AyahContent {
  final String arabicText;
  final String translation;

  const AyahContent({required this.arabicText, required this.translation});
}

/// Resolves the Ayah content to show for a given alarm. The Quran verse
/// database is a separate content layer that hasn't been built yet, so this
/// listener takes it as an injected dependency rather than hardcoding it.
typedef AyahContentResolver = Future<AyahContent> Function(AlarmModel alarm);

/// Bridges the native `alarm` package's ringing stream into our Riverpod
/// state machine: whenever the system clock fires a scheduled alarm, this
/// finds the matching [AlarmModel], resolves its Ayah content, and drives
/// [AlarmStateNotifier.triggerAlarmSession] — so the rest of the app reacts
/// through the state machine rather than the native alarm APIs directly.
///
/// Also the entry point for a Dead Man's Switch alarm firing (see
/// `AlarmStateNotifier.startVoiceCapture`/`scheduleDeadMansSwitchAlarm`):
/// that's a *second* native alarm scheduled under its own id, so it flows
/// through this exact same stream and needs its own id-matching pass to
/// route to [AlarmStateNotifier.handleDeadMansSwitchFired] instead.
class AlarmRingingListener {
  final DatabaseService databaseService;
  final AlarmStateNotifier alarmStateNotifier;
  final AyahContentResolver resolveAyahContent;

  StreamSubscription<AlarmSet>? _subscription;

  AlarmRingingListener({
    required this.databaseService,
    required this.alarmStateNotifier,
    required this.resolveAyahContent,
  });

  /// Starts listening to [Alarm.ringing]. Call [dispose] before starting
  /// again to avoid a duplicate subscription.
  void start() {
    _subscription = Alarm.ringing.listen(_handleRingingAlarms);
  }

  Future<void> _handleRingingAlarms(AlarmSet ringingAlarms) async {
    for (final AlarmSettings ringingAlarm in ringingAlarms.alarms) {
      final AlarmModel? primaryMatch = _findMatchingAlarm(
        ringingAlarm.id,
        AlarmHardwareService.nativeAlarmIdFor,
      );
      if (primaryMatch != null) {
        final AyahContent content = await resolveAyahContent(primaryMatch);
        alarmStateNotifier.triggerAlarmSession(
          primaryMatch,
          content.arabicText,
          content.translation,
        );
        continue;
      }

      // Not the primary wake alarm — check whether this is one alarm's
      // Dead Man's Switch firing instead (the grace-period safety net
      // armed by `AlarmStateNotifier.startVoiceCapture`). It has its own,
      // never-overlapping id space, so an alarm can never match both.
      final AlarmModel? fallbackMatch = _findMatchingAlarm(
        ringingAlarm.id,
        AlarmHardwareService.nativeFallbackAlarmIdFor,
      );
      if (fallbackMatch == null) continue;

      final AyahContent content = await resolveAyahContent(fallbackMatch);
      alarmStateNotifier.handleDeadMansSwitchFired(
        fallbackMatch,
        content.arabicText,
        content.translation,
      );
    }
  }

  AlarmModel? _findMatchingAlarm(
    int nativeAlarmId,
    int Function(String alarmModelId) idMapper,
  ) {
    for (final AlarmModel alarm in databaseService.getAllAlarms()) {
      if (idMapper(alarm.id) == nativeAlarmId) {
        return alarm;
      }
    }
    return null;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
