import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/domain/streaks.dart';

import '../helpers/fixtures.dart';

void main() {
  // 2026-01-05 is a Monday.
  group('daily', () {
    final h = habit(startDate: d(2026, 1, 1));

    test('no completions -> 0', () {
      const l = CompletionLog.empty();
      expect(currentStreak(h, l, d(2026, 1, 10)), 0);
      expect(bestStreak(h, l, d(2026, 1, 10)), 0);
    });

    test('today not yet done does not break the current streak', () {
      final l = log({'h1': range(d(2026, 1, 1), d(2026, 1, 9))});
      expect(currentStreak(h, l, d(2026, 1, 10)), 9);
      expect(currentStreak(h, l, d(2026, 1, 9)), 9);
    });

    test('today done extends the streak', () {
      final l = log({'h1': range(d(2026, 1, 1), d(2026, 1, 10))});
      expect(currentStreak(h, l, d(2026, 1, 10)), 10);
    });

    test('yesterday missed breaks the streak', () {
      final l = log({'h1': range(d(2026, 1, 1), d(2026, 1, 8))});
      expect(currentStreak(h, l, d(2026, 1, 10)), 0);
      expect(bestStreak(h, l, d(2026, 1, 10)), 8);
    });

    test('best streak picks the longest run', () {
      final l = log({
        'h1': [
          ...range(d(2026, 1, 1), d(2026, 1, 3)),
          ...range(d(2026, 1, 5), d(2026, 1, 11)),
          ...range(d(2026, 1, 13), d(2026, 1, 14)),
        ],
      });
      expect(bestStreak(h, l, d(2026, 1, 14)), 7);
      expect(currentStreak(h, l, d(2026, 1, 14)), 2);
    });

    test('crosses month and year boundaries', () {
      final h2 = habit(startDate: d(2025, 12, 1));
      final l = log({'h1': range(d(2025, 12, 20), d(2026, 2, 3))});
      expect(currentStreak(h2, l, d(2026, 2, 3)), 46);
      expect(bestStreak(h2, l, d(2026, 2, 3)), 46);
    });

    test('across DST transitions', () {
      final h2 = habit(startDate: d(2026, 3, 1));
      final l = log({'h1': range(d(2026, 3, 1), d(2026, 11, 30))});
      expect(currentStreak(h2, l, d(2026, 11, 30)), 275);
      expect(bestStreak(h2, l, d(2026, 11, 30)), 275);
    });

    test('completions before startDate and after today are ignored', () {
      final h2 = habit(startDate: d(2026, 1, 5));
      final l = log({
        'h1': [...range(d(2026, 1, 1), d(2026, 1, 6)), d(2026, 1, 20)],
      });
      expect(currentStreak(h2, l, d(2026, 1, 7)), 2);
      expect(bestStreak(h2, l, d(2026, 1, 7)), 2);
    });

    test('today before startDate -> 0', () {
      final h2 = habit(startDate: d(2026, 2, 1));
      expect(currentStreak(h2, log({'h1': [d(2026, 1, 31)]}), d(2026, 1, 31)), 0);
    });

    test('accepts a today with a time of day', () {
      final l = log({'h1': range(d(2026, 1, 1), d(2026, 1, 3))});
      expect(currentStreak(h, l, DateTime(2026, 1, 3, 23, 59)), 3);
    });
  });

  group('weekdays', () {
    // Mon, Wed, Fri
    final h = habit(schedule: WeekdaysSchedule({1, 3, 5}), startDate: d(2026, 1, 5));

    test('non-scheduled days never break the streak', () {
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 7), d(2026, 1, 9), d(2026, 1, 12)]});
      // Sun 11th and Tue 13th are not scheduled.
      expect(currentStreak(h, l, d(2026, 1, 13)), 4);
      expect(bestStreak(h, l, d(2026, 1, 13)), 4);
    });

    test('today (scheduled, not done) does not break; missed scheduled day does', () {
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 7)]});
      expect(currentStreak(h, l, d(2026, 1, 9)), 2); // Fri today, not done
      expect(currentStreak(h, l, d(2026, 1, 10)), 0); // Fri missed
    });

    test('check-ins on non-scheduled days do not count', () {
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 7)]});
      expect(currentStreak(h, l, d(2026, 1, 8)), 2);
      expect(bestStreak(h, l, d(2026, 1, 8)), 2);
    });
  });

  group('every N days', () {
    final h = habit(schedule: EveryNDaysSchedule(3), startDate: d(2026, 1, 30));

    test('counts scheduled occurrences across a month boundary', () {
      // Due: Jan 30, Feb 2, Feb 5, Feb 8.
      final l = log({'h1': [d(2026, 1, 30), d(2026, 2, 2), d(2026, 2, 5)]});
      expect(currentStreak(h, l, d(2026, 2, 7)), 3);
      expect(currentStreak(h, l, d(2026, 2, 8)), 3); // today due, not done
      expect(currentStreak(h, l, d(2026, 2, 9)), 0); // Feb 8 missed
      expect(bestStreak(h, l, d(2026, 2, 9)), 3);
    });
  });

  group('times per week', () {
    // 2x/week, starting Monday 2026-01-05.
    final h = habit(schedule: TimesPerWeekSchedule(2), startDate: d(2026, 1, 5));

    test('counts consecutive successful ISO weeks', () {
      final l = log({
        'h1': [
          d(2026, 1, 5), d(2026, 1, 6), // week 1 ok
          d(2026, 1, 12), d(2026, 1, 18), // week 2 ok (Mon + Sun)
          d(2026, 1, 21), d(2026, 1, 22), d(2026, 1, 23), // week 3 ok
        ],
      });
      expect(streakUnitOf(h), StreakUnit.weeks);
      expect(currentStreak(h, l, d(2026, 1, 25)), 3);
      expect(bestStreak(h, l, d(2026, 1, 25)), 3);
    });

    test('current week in progress does not break the streak', () {
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 12), d(2026, 1, 13)]});
      // Week of Jan 19: nothing yet.
      expect(currentStreak(h, l, d(2026, 1, 21)), 2);
      // Week of Jan 19: one check-in, still in progress.
      final l2 = l.withCompletion('h1', d(2026, 1, 20), true);
      expect(currentStreak(h, l2, d(2026, 1, 25)), 2);
      // Target reached in the current week -> counts.
      final l3 = l2.withCompletion('h1', d(2026, 1, 21), true);
      expect(currentStreak(h, l3, d(2026, 1, 21)), 3);
    });

    test('a failed past week breaks the streak', () {
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 12), d(2026, 1, 19), d(2026, 1, 20)]});
      expect(currentStreak(h, l, d(2026, 1, 26)), 1);
      expect(bestStreak(h, l, d(2026, 1, 26)), 1);
    });

    test('week spanning the year boundary', () {
      final h2 = habit(schedule: TimesPerWeekSchedule(2), startDate: d(2025, 12, 22));
      final l = log({
        'h1': [
          d(2025, 12, 22), d(2025, 12, 24),
          d(2025, 12, 31), d(2026, 1, 2), // Mon 29 Dec .. Sun 4 Jan
          d(2026, 1, 5), d(2026, 1, 9),
        ],
      });
      expect(currentStreak(h2, l, d(2026, 1, 9)), 3);
      expect(bestStreak(h2, l, d(2026, 1, 11)), 3);
    });

    test('partial first week only needs the days available', () {
      // Starts on Saturday: only 2 days left in that week, target 3.
      final h2 = habit(schedule: TimesPerWeekSchedule(3), startDate: d(2026, 1, 10));
      final l = log({
        'h1': [d(2026, 1, 10), d(2026, 1, 11), d(2026, 1, 12), d(2026, 1, 13), d(2026, 1, 14)],
      });
      expect(currentStreak(h2, l, d(2026, 1, 19)), 2);
      // Only one of the two available days -> first week fails.
      final l2 = l.withCompletion('h1', d(2026, 1, 11), false);
      expect(currentStreak(h2, l2, d(2026, 1, 19)), 1);
    });

    test('check-ins before startDate do not count toward the first week', () {
      final h2 = habit(schedule: TimesPerWeekSchedule(2), startDate: d(2026, 1, 7));
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 7)]});
      expect(currentStreak(h2, l, d(2026, 1, 12)), 0);
    });
  });

  test('streakInfo bundles current, best and unit', () {
    final h = habit(startDate: d(2026, 1, 1));
    final l = log({'h1': [...range(d(2026, 1, 1), d(2026, 1, 4)), d(2026, 1, 6)]});
    expect(
      streakInfo(h, l, d(2026, 1, 6)),
      const StreakInfo(current: 1, best: 4, unit: StreakUnit.days),
    );
  });
}
