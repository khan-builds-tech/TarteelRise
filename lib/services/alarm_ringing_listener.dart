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
      final AlarmModel? matchedAlarm = _findMatchingAlarm(ringingAlarm.id);
      if (matchedAlarm == null) continue;

      final AyahContent content = await resolveAyahContent(matchedAlarm);
      alarmStateNotifier.triggerAlarmSession(
        matchedAlarm,
        content.arabicText,
        content.translation,
      );
    }
  }

  AlarmModel? _findMatchingAlarm(int nativeAlarmId) {
    for (final AlarmModel alarm in databaseService.getAllAlarms()) {
      if (AlarmHardwareService.nativeAlarmIdFor(alarm.id) == nativeAlarmId) {
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
