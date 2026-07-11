import 'package:hive/hive.dart';

part 'user_stats_model.g.dart';

@HiveType(typeId: 1)
class UserStatsModel extends HiveObject {
  @HiveField(0)
  int streakCount;

  @HiveField(1)
  String? lastRecitedDate;

  @HiveField(2)
  int highestStreak;

  UserStatsModel({
    this.streakCount = 0,
    this.lastRecitedDate,
    this.highestStreak = 0,
  });
}
