import 'dart:async';
import 'dart:io' show Platform;

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/alarm_model.dart';

/// Wraps the `alarm` package's native scheduling (and, via its iOS backend,
/// AlarmKit) behind a single hardware-facing service, so nothing else in the
/// app talks to platform alarm APIs directly.
class AlarmHardwareService {
  static const String adhanAssetPath = 'assets/audio/adhan.mp3';

  /// Backs [hasFullScreenIntentPermission]/[requestFullScreenIntentPermission].
  /// Android 14+'s full-screen-intent special permission has no
  /// `permission_handler` support (it isn't a runtime dialog, just a
  /// check + a Settings deep link), so those two native calls live directly
  /// in `MainActivity.kt` behind this channel.
  static const MethodChannel _fullScreenIntentChannel =
      MethodChannel('com.tarteelrise.tarteel_rise/full_screen_intent');

  /// Plays the Adhan locally when [resumeAdhanPlayback] fires — deliberately
  /// NOT the native `alarm` package, which was already stopped via
  /// [stopActiveAlarmSound] once the user started reciting. Re-triggering a
  /// *new* native alarm just to ring "right now" would be a hack (that API
  /// is for scheduling future times) and would loop back through
  /// `AlarmRingingListener` into a session that's already active.
  /// Lazy — `AudioPlayer()` initializes a native audio session, which
  /// needs a Flutter binding to already exist. Most alarm sessions
  /// complete before ever needing this, so it's only constructed the
  /// first time [resumeAdhanPlayback]/[stopResumedAdhanPlayback] actually
  /// runs, rather than eagerly whenever [AlarmHardwareService] itself is.
  AudioPlayer? _resumePlayer;
  AudioPlayer get _resumePlayerInstance => _resumePlayer ??= AudioPlayer();

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

  /// Re-registers every enabled alarm's next fire time. The `alarm` package
  /// has no native day-of-week recurrence, so this must run on each cold
  /// launch (and after an alarm fires) to roll one-shot schedules forward.
  Future<void> rescheduleAllEnabledAlarms(List<AlarmModel> alarms) async {
    for (final AlarmModel alarm in alarms) {
      if (alarm.isEnabled) {
        await scheduleMorningAlarm(alarm);
      }
    }
  }

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

  /// Prompts the user to exempt the app from Android's battery
  /// optimizations — without it, the OS can still defer or kill the
  /// alarm's background work on some OEM skins even with the foreground
  /// service types declared. No-op on iOS, where this permission doesn't
  /// exist. Fails safe: a denied/unavailable permission just leaves the
  /// exemption unset rather than throwing.
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.requestBatteryOptimizationExemption failed: $error\n$stackTrace',
      );
    }
  }

  /// Prompts the user to grant the "Alarms & reminders" exact-alarm
  /// permission if it isn't already — call once during app bootstrap,
  /// before the first [scheduleMorningAlarm].
  ///
  /// This exists because the underlying `alarm` package's native Android
  /// scheduling call silently swallows a missing/revoked exact-alarm
  /// permission: `AlarmApiImpl.setAlarm` calls back
  /// `Result.success(Unit)` *unconditionally*, even when the
  /// `AlarmManager.setExactAndAllowWhileIdle` call inside throws a
  /// `SecurityException` — that exception is caught and only logged on
  /// the native side, never surfaced back through the platform channel.
  /// So `Alarm.set()` reports success while genuinely scheduling nothing.
  /// [_setNativeAlarm] checks [hasExactAlarmPermission] itself before ever
  /// calling into the plugin, for exactly this reason — this method is
  /// what gets the permission granted in the first place so that check
  /// normally passes. No-op on iOS, where this permission doesn't exist.
  Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;
    try {
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.requestExactAlarmPermission failed: $error\n$stackTrace',
      );
    }
  }

  /// Requests the runtime notification permission. The manifest already
  /// declares `POST_NOTIFICATIONS`, but Android 13+ also requires this
  /// runtime grant — without it, the alarm's own foreground-service
  /// notification (required for it to keep running/ringing while the app
  /// is backgrounded or killed) can fail to post, which can silently stop
  /// the alarm from firing at all rather than just hiding a notification.
  /// No-op (fails open) if the check/request itself fails, same as
  /// [requestBatteryOptimizationExemption].
  Future<void> requestNotificationPermission() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.requestNotificationPermission failed: $error\n$stackTrace',
      );
    }
  }

  /// Whether the exact-alarm permission is currently granted. Always
  /// `true` on iOS (the concept doesn't exist there) or if the permission
  /// check itself fails — fails open rather than blocking every alarm
  /// from ever scheduling just because the check couldn't run; the native
  /// call being attempted afterward is still wrapped in its own
  /// try/catch/timeout regardless.
  Future<bool> hasExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await Permission.scheduleExactAlarm.isGranted;
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.hasExactAlarmPermission failed: $error\n$stackTrace',
      );
      return true;
    }
  }

  /// Whether Android will actually honor `androidFullScreenIntent: true` and
  /// auto-launch the ringing screen over the lock screen. Always `true` on
  /// iOS, on Android below API 34 (where the manifest declaration alone is
  /// sufficient), or if the check itself fails — fails open for the same
  /// reason [hasExactAlarmPermission] does, since a failed check must never
  /// block scheduling outright. On API 34+, the OS can silently downgrade a
  /// fired alarm to an ordinary heads-up notification if this is `false`:
  /// the alarm is still genuinely ringing (foreground service, audio, all
  /// native and isolate-independent), it just won't wake the screen or show
  /// [AlarmActiveScreen] until the user unlocks and opens the app themselves.
  Future<bool> hasFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _fullScreenIntentChannel
              .invokeMethod<bool>('canUseFullScreenIntent')
              .timeout(nativeCallTimeout) ??
          true;
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.hasFullScreenIntentPermission failed: $error\n$stackTrace',
      );
      return true;
    }
  }

  /// Deep-links to the one Settings screen
  /// (`ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`) that lets the user grant
  /// the permission [hasFullScreenIntentPermission] checks — there is no
  /// in-app dialog Android exposes for this, unlike
  /// [requestBatteryOptimizationExemption]/[requestExactAlarmPermission].
  /// No-op on iOS or pre-API-34 Android. Fails safe: a failed/unsupported
  /// call just leaves the permission unset rather than throwing.
  Future<void> requestFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _fullScreenIntentChannel
          .invokeMethod<void>('openFullScreenIntentSettings')
          .timeout(nativeCallTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.requestFullScreenIntentPermission failed: $error\n$stackTrace',
      );
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

    final DateTime triggerTime = _nextTriggerDateTime(
      hour: alarmSettings.hour,
      minute: alarmSettings.minute,
      daysOfWeek: alarmSettings.daysOfWeek,
    );

    return _setNativeAlarm(
      id: nativeAlarmIdFor(alarmSettings.id),
      dateTime: triggerTime,
      callerName: 'scheduleMorningAlarm',
    );
  }

  /// Arms the "Dead Man's Switch" safety net: a *second*, independent
  /// native alarm — same exact/wakeup scheduling, same looping Adhan, same
  /// full-screen-intent foreground service as [scheduleMorningAlarm] —
  /// firing [fallbackDelay] from now under its own id
  /// ([nativeFallbackAlarmIdFor], never the same id as the primary alarm).
  ///
  /// [fallbackDelay] must match (or very slightly exceed) the caller's own
  /// in-app grace period, never a shorter, independent duration — this is
  /// meant purely as backup for "the Dart timer didn't fire," not a
  /// second, earlier deadline. A hardcoded delay shorter than the actual
  /// grace period fires this mid-recitation, resuming the Adhan under a
  /// native alarm id `pauseAdhanForReview` doesn't know about, while the
  /// user is still legitimately, successfully reciting.
  ///
  /// Call this the moment the user opens the mic to recite. If a validated
  /// recitation (or the Emergency Snooze fallback) completes first, the
  /// caller must cancel it via [cancelDeadMansSwitchAlarm]. If it fires
  /// unopposed — the user stopped reciting, fell back asleep, or the app
  /// process was killed entirely — this alarm is scheduled through the
  /// native `alarm` package, so the Adhan resumes and the lock-screen
  /// wake-up UI is forced back into focus via its own native foreground
  /// service and full-screen intent, with zero dependency on the Dart
  /// isolate that armed it still being alive.
  Future<bool> scheduleDeadMansSwitchAlarm(
    AlarmModel alarmSettings, {
    required Duration fallbackDelay,
  }) {
    return _setNativeAlarm(
      id: nativeFallbackAlarmIdFor(alarmSettings.id),
      dateTime: DateTime.now().add(fallbackDelay),
      callerName: 'scheduleDeadMansSwitchAlarm',
    );
  }

  /// Cancels any *native* alarm (primary or Dead Man's Switch) left over
  /// from a deleted alarm, or a disabled one whose own cancel call failed —
  /// the actual "ghost trigger" risk. Our own Hive [AlarmModel]s are
  /// recurring rules (hour/minute/days), not one-shot fire times, so
  /// nothing stored in Hive itself can go stale/expired the way a one-shot
  /// alarm could; [rescheduleAllEnabledAlarms] already recomputes every
  /// enabled alarm's next fire time fresh from `DateTime.now()` on every
  /// cold launch. What *can* go stale is the native `alarm` package's own
  /// persisted schedule, if a `cancelScheduledAlarm`/`cancelDeadMansSwitchAlarm`
  /// call was made but the app was killed before the native side confirmed
  /// it, or a Hive record was removed some other way.
  ///
  /// [allAlarms] should be every alarm currently in Hive, enabled or not.
  /// A Dead Man's Switch id is left alone as long as its parent alarm still
  /// exists at all (even disabled) — there is no reliable way to tell
  /// "orphaned" apart from "legitimately about to fire because the app was
  /// just killed mid-recitation" purely from Hive state, and silently
  /// cancelling a real one would defeat the safety net it exists for. Only
  /// a primary schedule for a now-*disabled* alarm, or any native alarm
  /// with no matching Hive record left at all, is unambiguous.
  Future<void> purgeOrphanedNativeAlarms(List<AlarmModel> allAlarms) async {
    try {
      final Set<int> expectedEnabledIds = allAlarms
          .where((alarm) => alarm.isEnabled)
          .map((alarm) => nativeAlarmIdFor(alarm.id))
          .toSet();
      final Set<int> possibleDeadMansSwitchIds =
          allAlarms.map((alarm) => nativeFallbackAlarmIdFor(alarm.id)).toSet();

      final List<AlarmSettings> scheduled =
          await Alarm.getAlarms().timeout(nativeCallTimeout);
      for (final AlarmSettings native in scheduled) {
        final bool isExpectedPrimary = expectedEnabledIds.contains(native.id);
        final bool isPossibleDeadMansSwitch =
            possibleDeadMansSwitchIds.contains(native.id);
        if (!isExpectedPrimary && !isPossibleDeadMansSwitch) {
          await Alarm.stop(native.id).timeout(nativeCallTimeout);
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.purgeOrphanedNativeAlarms failed: $error\n$stackTrace',
      );
    }
  }

  /// Shared native-scheduling path for both [scheduleMorningAlarm] and
  /// [scheduleDeadMansSwitchAlarm] — they differ only in which id and
  /// `dateTime` they schedule under; every audio/volume/foreground-service
  /// setting that matters for "must still ring if the app is dead" is
  /// identical between them.
  Future<bool> _setNativeAlarm({
    required int id,
    required DateTime dateTime,
    required String callerName,
  }) async {
    // Checked *before* ever calling into the plugin: `Alarm.set()` reports
    // success unconditionally even when the native
    // `AlarmManager.setExactAndAllowWhileIdle` call it makes internally
    // throws from a missing/revoked exact-alarm permission (see
    // [hasExactAlarmPermission]'s doc comment) — so this is the only way
    // to actually detect that failure and return `false` truthfully,
    // rather than trusting a lie.
    if (!await hasExactAlarmPermission()) {
      debugPrint(
        'AlarmHardwareService.$callerName failed: exact-alarm permission not granted.',
      );
      return false;
    }

    try {
      final AlarmSettings nativeSettings = AlarmSettings(
        id: id,
        dateTime: dateTime,
        assetAudioPath: adhanAssetPath,
        loopAudio: true,
        // Shows a rescue notification if the app process is killed while
        // this alarm is still pending, and lets the ringing screen turn the
        // device on over the lock screen even if the main activity was
        // dead when the native alarm fired.
        warningNotificationOnKill: true,
        androidFullScreenIntent: true,
        // Ensures this alarm still rings even if another one happens to be
        // ringing at the same moment — most relevant for the Dead Man's
        // Switch fallback, which must always fire regardless of whatever
        // else might coincidentally be active.
        allowAlarmOverlap: true,
        // Defaults to `true` in the `alarm` package, which stops the native
        // alarm the moment Android tears down the app's task — defeating
        // the whole point of surviving a swipe-away kill. Must be `false`
        // so the alarm keeps ringing from its own foreground service.
        androidStopAlarmOnTermination: false,
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
      debugPrint('AlarmHardwareService.$callerName failed: $error\n$stackTrace');
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
  /// [alarmId] (a native id produced by [nativeAlarmIdFor]) — and, best
  /// effort, any locally resumed Adhan from [resumeAdhanPlayback] too, so
  /// silencing the alarm always silences whichever audio source is
  /// actually active.
  Future<bool> stopActiveAlarmSound(int alarmId) async {
    // Only touch the resume player if it was already constructed — most
    // sessions complete without ever calling [resumeAdhanPlayback], and
    // touching [_resumePlayerInstance] here would defeat its laziness.
    if (_resumePlayer != null) {
      unawaited(stopResumedAdhanPlayback());
    }
    try {
      return await Alarm.stop(alarmId).timeout(nativeCallTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.stopActiveAlarmSound failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  /// Cancels the pending native schedule for [alarmId] (our Hive
  /// [AlarmModel.id], not the native int id) — used when the user deletes
  /// an alarm from the dashboard. Delegates to
  /// [stopActiveAlarmSound]: the `alarm` package exposes only one native
  /// "remove this id" call, used whether the alarm is currently ringing or
  /// merely scheduled for later. Safe to call even if nothing is currently
  /// scheduled for [alarmId].
  Future<bool> cancelScheduledAlarm(String alarmId) =>
      stopActiveAlarmSound(nativeAlarmIdFor(alarmId));

  /// Disarms the Dead Man's Switch armed by [scheduleDeadMansSwitchAlarm]
  /// for [alarmId] — called the moment recitation is validated (or the
  /// Emergency Snooze fallback completes), so the safety-net alarm never
  /// fires and re-rings an already-silenced session. Safe to call even if
  /// nothing is currently scheduled under this id.
  Future<bool> cancelDeadMansSwitchAlarm(String alarmId) =>
      stopActiveAlarmSound(nativeFallbackAlarmIdFor(alarmId));

  /// Resumes the Adhan locally (looping, via just_audio) when a recitation
  /// session times out without completing. See [_resumePlayer] for why
  /// this doesn't go through the native `alarm` package.
  Future<void> resumeAdhanPlayback() async {
    try {
      await _resumePlayerInstance.setAsset(adhanAssetPath);
      await _resumePlayerInstance.setLoopMode(LoopMode.one);
      await _resumePlayerInstance.setVolume(1.0);
      await _resumePlayerInstance.play();
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.resumeAdhanPlayback failed: $error\n$stackTrace',
      );
    }
  }

  /// Stops audio started by [resumeAdhanPlayback]. Safe to call even if it
  /// was never started.
  Future<void> stopResumedAdhanPlayback() async {
    try {
      await _resumePlayerInstance.stop();
    } catch (error, stackTrace) {
      debugPrint(
        'AlarmHardwareService.stopResumedAdhanPlayback failed: $error\n$stackTrace',
      );
    }
  }

  /// Same as [stopResumedAdhanPlayback], but only if the resume player was
  /// ever actually constructed — mirrors the guard [stopActiveAlarmSound]
  /// already uses around it. Most sessions never call
  /// [resumeAdhanPlayback] at all, so a caller wanting to guarantee "every
  /// audio path is stopped" (e.g. [AudioService.stopAllAudio]) must not
  /// force [_resumePlayerInstance]'s lazy construction just to immediately
  /// stop a player that was never playing anything.
  Future<void> stopResumedAdhanPlaybackIfActive() async {
    if (_resumePlayer != null) {
      await stopResumedAdhanPlayback();
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

  /// Derives the Dead Man's Switch's own native id for our Hive
  /// [AlarmModel.id] — deliberately a *different* id than
  /// [nativeAlarmIdFor] (via a distinguishing suffix fed into the same
  /// hash), since `Alarm.set` replaces any existing native alarm that
  /// shares an id. The primary wake alarm and its safety-net fallback must
  /// stay independently addressable so cancelling one can never touch the
  /// other.
  static int nativeFallbackAlarmIdFor(String id) =>
      nativeAlarmIdFor('$id::deadmans-switch');

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
