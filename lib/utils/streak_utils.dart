/// Pure streak-continuation logic, isolated from Hive I/O so it's directly
/// testable without a database.
library;

/// Formats [date] as an ISO `YYYY-MM-DD` string (local calendar day, no
/// time component) — the format [UserStatsModel.lastRecitedDate] is
/// stored in.
String formatIsoDate(DateTime date) {
  final String year = date.year.toString().padLeft(4, '0');
  final String month = date.month.toString().padLeft(2, '0');
  final String day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// The streak count that should be recorded for [today], given the
/// current streak and when it was last recorded:
/// - Unchanged if [lastRecitedDate] is already today (a second alarm
///   firing the same morning can't double-count).
/// - [currentStreak] + 1 if [lastRecitedDate] was the day before [today]
///   (a real continuation).
/// - 1 otherwise — a gap in days, or this is the first recitation ever.
int computeStreakForToday({
  required int currentStreak,
  required String? lastRecitedDate,
  required DateTime today,
}) {
  final String todayString = formatIsoDate(today);
  if (lastRecitedDate == todayString) {
    return currentStreak;
  }

  final String yesterdayString = formatIsoDate(today.subtract(const Duration(days: 1)));
  final bool isConsecutiveDay = lastRecitedDate == yesterdayString;
  return isConsecutiveDay ? currentStreak + 1 : 1;
}
