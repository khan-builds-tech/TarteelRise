import 'package:hive_flutter/hive_flutter.dart';

import '../models/alarm_model.dart';
import '../models/user_stats_model.dart';

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

  Future<void> init() async {
    await Hive.initFlutter();

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
}
