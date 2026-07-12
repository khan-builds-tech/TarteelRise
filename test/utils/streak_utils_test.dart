import 'package:flutter_test/flutter_test.dart';
import 'package:tarteel_rise/utils/streak_utils.dart';

void main() {
  group('formatIsoDate', () {
    test('pads month and day to two digits', () {
      expect(formatIsoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('computeStreakForToday', () {
    test('starts a fresh streak at 1 when there is no prior record', () {
      final int streak = computeStreakForToday(
        currentStreak: 0,
        lastRecitedDate: null,
        today: DateTime(2026, 3, 10),
      );
      expect(streak, 1);
    });

    test('increments the streak when the last recitation was yesterday', () {
      final int streak = computeStreakForToday(
        currentStreak: 4,
        lastRecitedDate: '2026-03-09',
        today: DateTime(2026, 3, 10),
      );
      expect(streak, 5);
    });

    test('resets to 1 when there is a gap of more than one day', () {
      final int streak = computeStreakForToday(
        currentStreak: 12,
        lastRecitedDate: '2026-03-01',
        today: DateTime(2026, 3, 10),
      );
      expect(streak, 1);
    });

    test('leaves the streak unchanged if today was already recorded', () {
      final int streak = computeStreakForToday(
        currentStreak: 7,
        lastRecitedDate: '2026-03-10',
        today: DateTime(2026, 3, 10),
      );
      expect(streak, 7);
    });

    test('rolls over correctly across a month boundary', () {
      final int streak = computeStreakForToday(
        currentStreak: 2,
        lastRecitedDate: '2026-02-28',
        today: DateTime(2026, 3, 1),
      );
      expect(streak, 3);
    });
  });
}
