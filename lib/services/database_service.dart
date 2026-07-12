import 'package:hive_flutter/hive_flutter.dart';

import '../models/alarm_model.dart';
import '../models/user_stats_model.dart';
import '../utils/streak_utils.dart';

/// Offline-first storage for alarm configurations and user recitation stats.
///
/// Backed by two Hive boxes: [alarmsBoxName] holds one [AlarmModel] per
/// scheduled alarm keyed by its `id`; [statsBoxName] holds a single
/// [UserStatsModel] keyed by [_statsKey], since streak tracking is per-device
/// rather than per-alarm.
class DatabaseService {
  static const String alarmsBoxName = 'alarms_box';
  static const String statsBoxName = 'stats_box';
  static const String _statsKey = 'current';

  late Box<AlarmModel> _alarmsBox;
  late Box<UserStatsModel> _statsBox;

  /// [testHiveDirectoryPath], if given, calls the plain [Hive.init] against
  /// that directory instead of [Hive.initFlutter] — [Hive.initFlutter]
  /// resolves the platform's app-documents directory via `path_provider`,
  /// which needs a real platform channel and isn't available in
  /// `flutter test`. Production code should never pass this.
  Future<void> init({String? testHiveDirectoryPath}) async {
    if (testHiveDirectoryPath != null) {
      Hive.init(testHiveDirectoryPath);
    } else {
      await Hive.initFlutter();
    }

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AlarmModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(UserStatsModelAdapter());
    }

    _alarmsBox = await Hive.openBox<AlarmModel>(alarmsBoxName);
    _statsBox = await Hive.openBox<UserStatsModel>(statsBoxName);
  }

  Future<void> saveAlarm(AlarmModel alarm) async {
    await _alarmsBox.put(alarm.id, alarm);
  }

  Future<void> deleteAlarm(String id) async {
    await _alarmsBox.delete(id);
  }

  List<AlarmModel> getAllAlarms() {
    return _alarmsBox.values.toList();
  }

  UserStatsModel getUserStats() {
    return _statsBox.get(_statsKey) ?? UserStatsModel();
  }

  Future<void> updateStreak(int newStreak, String dateString) async {
    final UserStatsModel stats = getUserStats();
    stats.streakCount = newStreak;
    stats.lastRecitedDate = dateString;
    if (newStreak > stats.highestStreak) {
      stats.highestStreak = newStreak;
    }
    await _statsBox.put(_statsKey, stats);
  }

  /// Call once a recitation clears its match threshold. Continues the
  /// streak if the last successful recitation was yesterday, resets to 1
  /// if there's a gap (or this is the first ever), and is a no-op if
  /// today was already recorded (e.g. a second alarm firing the same
  /// morning can't double-count).
  Future<UserStatsModel> recordSuccessfulRecitation() async {
    final UserStatsModel stats = getUserStats();
    final DateTime today = DateTime.now();

    final int newStreak = computeStreakForToday(
      currentStreak: stats.streakCount,
      lastRecitedDate: stats.lastRecitedDate,
      today: today,
    );

    await updateStreak(newStreak, formatIsoDate(today));
    return getUserStats();
  }

  /// Call when the user bypasses recitation via the Emergency Snooze text
  /// fallback. Breaks the current streak (resets to 0) to preserve the
  /// app's integrity, per the product spec, without touching
  /// [UserStatsModel.highestStreak] — that's a historical best, not the
  /// active streak. Clears `lastRecitedDate` so a later real recitation
  /// always restarts the streak at 1 rather than resuming a stale count.
  Future<UserStatsModel> recordEmergencySnooze() async {
    final UserStatsModel stats = getUserStats();
    stats.streakCount = 0;
    stats.lastRecitedDate = null;
    await _statsBox.put(_statsKey, stats);
    return stats;
  }
}
