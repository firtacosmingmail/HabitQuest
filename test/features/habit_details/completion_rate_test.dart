import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/domain/streaks.dart';
import 'package:habit_quest/features/habit_details/completion_rate.dart';
import 'package:habit_quest/features/habit_details/schedule_summary.dart';

import '../../helpers/fixtures.dart';

void main() {
  group('completionRate – day schedules', () {
    test('daily: completed days / scheduled days, today excluded if not done',
        () {
      final h = habit(startDate: d(2026, 1, 1));
      // Jan 1..10, done on 1..5 and 8. Today (10) not done → 9 days counted.
      final l = log({
        'h1': [...range(d(2026, 1, 1), d(2026, 1, 5)), d(2026, 1, 8)],
      });
      final r = completionRate(h, l, d(2026, 1, 10));
      expect(r, const CompletionRate(completed: 6, total: 9, unit: StreakUnit.days));
      expect(r.percent, 67);
    });

    test('today counts once it is done', () {
      final h = habit(startDate: d(2026, 1, 1));
      final l = log({'h1': [d(2026, 1, 3)]});
      expect(completionRate(h, l, d(2026, 1, 3)).ratio, closeTo(1 / 3, 1e-9));
    });

    test('first day, not yet done: nothing scheduled → null ratio', () {
      final h = habit(startDate: d(2026, 1, 1));
      final r = completionRate(h, log({}), d(2026, 1, 1));
      expect(r.total, 0);
      expect(r.ratio, isNull);
      expect(r.percent, isNull);
    });

    test('start date in the future → empty', () {
      final h = habit(startDate: d(2026, 2, 1));
      expect(completionRate(h, log({}), d(2026, 1, 1)).total, 0);
    });

    test('weekdays: only scheduled days count; off-day check-ins ignored', () {
      // Mon/Wed/Fri from Mon 2026-01-05; today Sun 2026-01-11.
      final h = habit(
        schedule: WeekdaysSchedule({1, 3, 5}),
        startDate: d(2026, 1, 5),
      );
      final l = log({
        'h1': [d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 9)],
      });
      final r = completionRate(h, l, d(2026, 1, 11));
      expect(r.completed, 2);
      expect(r.total, 3);
    });

    test('every N days counts from start date', () {
      // Every 3 days from Jan 1: Jan 1, 4, 7, 10.
      final h = habit(schedule: EveryNDaysSchedule(3), startDate: d(2026, 1, 1));
      final l = log({'h1': [d(2026, 1, 1), d(2026, 1, 7), d(2026, 1, 8)]});
      final r = completionRate(h, l, d(2026, 1, 10));
      // 10 is today and not done → excluded.
      expect(r.completed, 2);
      expect(r.total, 3);
    });

    test('check-ins before startDate are ignored', () {
      final h = habit(startDate: d(2026, 1, 5));
      final l = log({'h1': [d(2026, 1, 1), d(2026, 1, 5)]});
      final r = completionRate(h, l, d(2026, 1, 6));
      expect(r.completed, 1);
      expect(r.total, 1);
    });
  });

  group('completionRate – times per week', () {
    test('successful weeks / weeks; current week only once successful', () {
      // 2× per week from Mon 2026-01-05.
      // Week 1 (5–11): 2 → ok. Week 2 (12–18): 1 → fail.
      // Week 3 (19–25): 2 → ok. Current week (26–): 1 so far → not counted.
      final h = habit(
        schedule: TimesPerWeekSchedule(2),
        startDate: d(2026, 1, 5),
      );
      final l = log({
        'h1': [
          d(2026, 1, 5), d(2026, 1, 6),
          d(2026, 1, 14),
          d(2026, 1, 20), d(2026, 1, 25),
          d(2026, 1, 26),
        ],
      });
      final r = completionRate(h, l, d(2026, 1, 28));
      expect(r, const CompletionRate(completed: 2, total: 3, unit: StreakUnit.weeks));

      final done = log({
        'h1': [...l.datesFor('h1'), d(2026, 1, 27)],
      });
      expect(completionRate(h, done, d(2026, 1, 28)).total, 4);
      expect(completionRate(h, done, d(2026, 1, 28)).completed, 3);
    });

    test('partial first week needs only min(times, days left)', () {
      // 3× per week starting Sat 2026-01-10: first week has 2 days.
      final h = habit(
        schedule: TimesPerWeekSchedule(3),
        startDate: d(2026, 1, 10),
      );
      final l = log({'h1': [d(2026, 1, 10), d(2026, 1, 11)]});
      final r = completionRate(h, l, d(2026, 1, 12));
      expect(r.completed, 1);
      expect(r.total, 1);
    });
  });

  group('scheduleSummary', () {
    test('formats every schedule type', () {
      expect(scheduleSummary(const DailySchedule()), 'Every day');
      expect(scheduleSummary(WeekdaysSchedule({5, 1, 3})), 'Mon · Wed · Fri');
      expect(scheduleSummary(WeekdaysSchedule({1, 2, 3, 4, 5, 6, 7})),
          'Every day');
      expect(scheduleSummary(EveryNDaysSchedule(3)), 'Every 3 days');
      expect(scheduleSummary(EveryNDaysSchedule(1)), 'Every day');
      expect(scheduleSummary(TimesPerWeekSchedule(3)), '3× per week');
    });
  });
}
