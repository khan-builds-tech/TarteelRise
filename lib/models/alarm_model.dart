import 'package:hive/hive.dart';

part 'alarm_model.g.dart';

@HiveType(typeId: 0)
class AlarmModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  int hour;

  @HiveField(2)
  int minute;

  @HiveField(3)
  List<int> daysOfWeek;

  @HiveField(4)
  bool isEnabled;

  @HiveField(5)
  int selectedSurahIndex;

  @HiveField(6)
  String difficultyLevel;

  AlarmModel({
    required this.id,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    required this.isEnabled,
    required this.selectedSurahIndex,
    this.difficultyLevel = 'medium',
  });
}
