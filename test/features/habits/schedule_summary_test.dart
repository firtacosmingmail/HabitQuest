import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/domain/streaks.dart';
import 'package:habit_quest/features/habits/widgets/schedule_summary.dart';
import 'package:habit_quest/features/habits/widgets/streak_flame.dart';

import '../../helpers/fixtures.dart';

void main() {
  group('scheduleSummary', () {
    test('daily', () {
      expect(scheduleSummary(const DailySchedule()), 'Every day');
    });

    test('specific weekdays', () {
      expect(scheduleSummary(WeekdaysSchedule({5, 1, 3})), 'Mon · Wed · Fri');
      expect(scheduleSummary(WeekdaysSchedule({7})), 'Sun');
      expect(scheduleSummary(WeekdaysSchedule({1, 2, 3, 4, 5})), 'Weekdays');
      expect(scheduleSummary(WeekdaysSchedule({6, 7})), 'Weekends');
      expect(
        scheduleSummary(WeekdaysSchedule({1, 2, 3, 4, 5, 6, 7})),
        'Every day',
      );
    });

    test('every N days', () {
      expect(scheduleSummary(EveryNDaysSchedule(3)), 'Every 3 days');
      expect(scheduleSummary(EveryNDaysSchedule(1)), 'Every day');
    });

    test('times per week, with weekly progress', () {
      expect(scheduleSummary(TimesPerWeekSchedule(3)), '3× per week');
      expect(
        scheduleSummaryWithProgress(TimesPerWeekSchedule(3), (
          done: 1,
          target: 3,
        )),
        '3× per week · 1/3 this week',
      );
    });
  });

  test('weeklyProgress counts check-ins of the current ISO week', () {
    final h = habit(schedule: TimesPerWeekSchedule(3));
    // 2026-01-05 is a Monday; 01-04 belongs to the previous week.
    final l = log({
      'h1': [d(2026, 1, 4), d(2026, 1, 5), d(2026, 1, 7)],
    });
    expect(weeklyProgress(h, l, d(2026, 1, 7)), (done: 2, target: 3));
    expect(weeklyProgress(habit(), l, d(2026, 1, 7)), isNull);
  });

  test('streakLabel', () {
    expect(streakLabel(1, StreakUnit.days), '1 day');
    expect(streakLabel(5, StreakUnit.days), '5 days');
    expect(streakLabel(1, StreakUnit.weeks), '1 wk');
    expect(streakLabel(3, StreakUnit.weeks), '3 wks');
  });
}
