import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm_model.dart';
import '../models/user_stats_model.dart';
import 'alarm_state_provider.dart' show databaseServiceProvider;

/// Reactive view over the alarms persisted in Hive. [refresh] re-reads the
/// box — call it after any create/edit/delete flow mutates alarms.
class AlarmListNotifier extends StateNotifier<List<AlarmModel>> {
  final Ref ref;

  AlarmListNotifier(this.ref) : super(const <AlarmModel>[]) {
    refresh();
  }

  void refresh() {
    state = ref.read(databaseServiceProvider).getAllAlarms();
  }
}

final StateNotifierProvider<AlarmListNotifier, List<AlarmModel>>
    alarmListProvider =
    StateNotifierProvider<AlarmListNotifier, List<AlarmModel>>(
  (ref) => AlarmListNotifier(ref),
);

/// Reactive view over the single [UserStatsModel] record backing the
/// streak display.
class UserStatsNotifier extends StateNotifier<UserStatsModel> {
  final Ref ref;

  UserStatsNotifier(this.ref) : super(UserStatsModel()) {
    refresh();
  }

  void refresh() {
    state = ref.read(databaseServiceProvider).getUserStats();
  }
}

final StateNotifierProvider<UserStatsNotifier, UserStatsModel>
    userStatsProvider =
    StateNotifierProvider<UserStatsNotifier, UserStatsModel>(
  (ref) => UserStatsNotifier(ref),
);

/// Local UI selection for the Surah picker. Not yet wired to alarm
/// creation — there's no AlarmCreateScreen yet to consume this.
final StateProvider<int?> selectedSurahIndexProvider =
    StateProvider<int?>((ref) => null);
