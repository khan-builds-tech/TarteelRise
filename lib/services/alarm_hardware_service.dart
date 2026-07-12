import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

import '../models/alarm_model.dart';

/// Wraps the `alarm` package's native scheduling (and, via its iOS backend,
/// AlarmKit) behind a single hardware-facing service, so nothing else in the
/// app talks to platform alarm APIs directly.
class AlarmHardwareService {
  static const String adhanAssetPath = 'assets/audio/adhan.mp3';

  /// A stuck platform channel (missing plugin registration, an unresponsive
  /// native side) doesn't throw — it just never completes the `Future`,
  /// which `try`/`catch` can't do anything about. Every native call below
  /// is wrapped in [Future.timeout] specifically so a hang can never block
  /// the state machine forever; it becomes an ordinary, catchable
  /// [TimeoutException] instead. Overridable so tests don't have to wait
  /// out the real production duration against a channel that will never
  /// respond.
  final Duration nativeCallTimeout;

  AlarmHardwareService({this.nativeCallTimeout = const Duration(seconds: 10)});

  /// Registers the native alarm ports and reschedules any alarms that were
  /// still pending from a previous app session. Must be called once before
  /// [scheduleMorningAlarm] or [stopActiveAlarmSound] are used.
  Future<bool> initializeHardware() async {
    try {
      await Alarm.init().timeout(nativeCallTimeout);
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.initializeHardware failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  /// Translates [alarmSettings] (our Hive [AlarmModel]) into a native
  /// `alarm` package `AlarmSettings` and schedules it: the Adhan asset
  /// loops indefinitely, volume is pinned to maximum and enforced, and a
  /// notification is shown. Returns `false` without scheduling anything if
  /// [alarmSettings] is disabled or the native call fails.
  ///
  /// Deliberately does not attach a notification stop button — the product
  /// requires the user to recite the Ayah aloud to silence the alarm, so
  /// there must be no way to dismiss it from the notification alone.
  Future<bool> scheduleMorningAlarm(AlarmModel alarmSettings) async {
    if (!alarmSettings.isEnabled) {
      return false;
    }

    try {
      final DateTime triggerTime = _nextTriggerDateTime(
        hour: alarmSettings.hour,
        minute: alarmSettings.minute,
        daysOfWeek: alarmSettings.daysOfWeek,
      );

      final AlarmSettings nativeSettings = AlarmSettings(
        id: nativeAlarmIdFor(alarmSettings.id),
        dateTime: triggerTime,
        assetAudioPath: adhanAssetPath,
        loopAudio: true,
        volumeSettings: const VolumeSettings.fixed(
          volume: 1.0,
          volumeEnforced: true,
        ),
        notificationSettings: const NotificationSettings(
          title: 'Tarteel Rise',
          body: 'Recite the Ayah aloud to silence the alarm.',
        ),
      );

      return await Alarm.set(alarmSettings: nativeSettings).timeout(nativeCallTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.scheduleMorningAlarm failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  /// Silences the ringing Adhan the moment the user starts reciting, so it
  /// can't bleed into the microphone and corrupt the speech match.
  ///
  /// The `alarm` package's platform channel only exposes `setAlarm` /
  /// `stopAlarm` / `stopAll` — there is no live volume control on an alarm
  /// that is already ringing, so a true "duck to ~15%" isn't available.
  /// The only alternative (stop, then immediately re-schedule at low
  /// volume) audibly restarts the loop, which is worse than silence. So
  /// this fully stops the ringing audio; [stopActiveAlarmSound] is called
  /// again (harmlessly, `Alarm.stop` is a no-op if nothing is ringing) on
  /// completion.
  Future<bool> duckAlarmForRecitation(int alarmId) =>
      stopActiveAlarmSound(alarmId);

  /// Immediately stops the ringing Adhan audio for the alarm with
  /// [alarmId] (a native id produced by [nativeAlarmIdFor]).
  Future<bool> stopActiveAlarmSound(int alarmId) async {
    try {
      return await Alarm.stop(alarmId).timeout(nativeCallTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.stopActiveAlarmSound failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  /// Derives a stable, non-zero 31-bit native alarm id from our string
  /// [AlarmModel.id], since the `alarm` package requires an `int` id and
  /// forbids `0`/`-1`. Uses FNV-1a rather than [Object.hashCode] so the
  /// mapping is identical across app restarts and Dart versions — callers
  /// (e.g. matching a ringing alarm back to its [AlarmModel]) rely on that
  /// stability.
  static int nativeAlarmIdFor(String id) {
    int hash = 0x811c9dc5;
    for (final int codeUnit in id.codeUnits) {
      hash = (hash ^ codeUnit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final int positive = hash & 0x7FFFFFFF;
    return positive == 0 ? 1 : positive;
  }

  /// Finds the next `DateTime` at/after now matching [hour]:[minute] on one
  /// of [daysOfWeek] (ISO weekday: 1=Monday..7=Sunday). An empty
  /// [daysOfWeek] means "every day".
  ///
  /// The `alarm` package has no native day-of-week recurrence (confirmed in
  /// its own FAQ), so per its recommended pattern, callers are expected to
  /// re-run [scheduleMorningAlarm] on each app launch to roll this forward.
  static DateTime _nextTriggerDateTime({
    required int hour,
    required int minute,
    required List<int> daysOfWeek,
  }) {
    final DateTime now = DateTime.now();
    final DateTime todayAtTime =
        DateTime(now.year, now.month, now.day, hour, minute);

    if (daysOfWeek.isEmpty) {
      return todayAtTime.isAfter(now)
          ? todayAtTime
          : todayAtTime.add(const Duration(days: 1));
    }

    for (int offset = 0; offset < 8; offset++) {
      final DateTime candidate = todayAtTime.add(Duration(days: offset));
      if (daysOfWeek.contains(candidate.weekday) && candidate.isAfter(now)) {
        return candidate;
      }
    }

    // No valid ISO weekday (1-7) in daysOfWeek: fall back to "every day"
    // rather than silently failing to schedule.
    return todayAtTime.isAfter(now)
        ? todayAtTime
        : todayAtTime.add(const Duration(days: 1));
  }
}
