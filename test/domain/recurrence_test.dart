import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/domain/recurrence.dart';

import '../helpers/fixtures.dart';

void main() {
  // 2026-01-05 is a Monday.
  group('daily', () {
    final h = habit(startDate: d(2026, 1, 5));

    test('due every day from startDate, never before', () {
      expect(isDue(h, d(2026, 1, 4)), isFalse);
      expect(isDue(h, d(2026, 1, 5)), isTrue);
      expect(isDue(h, DateTime(2026, 1, 5, 23, 59)), isTrue);
      for (final x in range(d(2026, 1, 5), d(2027, 1, 5))) {
        expect(isDue(h, x), isTrue, reason: '$x');
      }
    });
  });

  group('weekdays', () {
    final h = habit(
      schedule: WeekdaysSchedule({DateTime.monday, DateTime.wednesday, DateTime.sunday}),
      startDate: d(2026, 1, 1), // Thursday
    );

    test('due only on chosen ISO weekdays', () {
      expect(isDue(h, d(2026, 1, 1)), isFalse); // Thu
      expect(isDue(h, d(2026, 1, 3)), isFalse); // Sat
      expect(isDue(h, d(2026, 1, 4)), isTrue); // Sun
      expect(isDue(h, d(2026, 1, 5)), isTrue); // Mon
      expect(isDue(h, d(2026, 1, 6)), isFalse); // Tue
      expect(isDue(h, d(2026, 1, 7)), isTrue); // Wed
    });

    test('not due before startDate even on a matching weekday', () {
      expect(isDue(h, d(2025, 12, 31)), isFalse); // Wed, before start
      expect(isDue(h, d(2025, 12, 29)), isFalse); // Mon, before start
    });

    test('works across a year boundary', () {
      final h2 = habit(schedule: WeekdaysSchedule({4}), startDate: d(2025, 12, 1));
      expect(isDue(h2, d(2026, 1, 1)), isTrue); // Thursday
      expect(isDue(h2, d(2025, 12, 31)), isFalse);
    });
  });

  group('every N days', () {
    test('counts from startDate', () {
      final h = habit(schedule: EveryNDaysSchedule(3), startDate: d(2026, 1, 30));
      expect(isDue(h, d(2026, 1, 27)), isFalse); // before start (multiple of 3)
      expect(isDue(h, d(2026, 1, 30)), isTrue);
      expect(isDue(h, d(2026, 1, 31)), isFalse);
      expect(isDue(h, d(2026, 2, 1)), isFalse);
      expect(isDue(h, d(2026, 2, 2)), isTrue); // across month boundary
      expect(isDue(h, d(2026, 2, 5)), isTrue);
    });

    test('n = 1 is daily', () {
      final h = habit(schedule: EveryNDaysSchedule(1), startDate: d(2026, 1, 1));
      expect(range(d(2026, 1, 1), d(2026, 3, 1)).every((x) => isDue(h, x)), isTrue);
    });

    test('stays aligned across DST changes and a leap year', () {
      final h = habit(schedule: EveryNDaysSchedule(7), startDate: d(2027, 12, 29));
      final due = range(d(2027, 12, 29), d(2029, 1, 10)).where((x) => isDue(h, x));
      // Every due date is the same weekday as the start (Wednesday).
      expect(due.every((x) => x.weekday == DateTime.wednesday), isTrue);
      expect(due.length, 55);
      expect(isDue(h, d(2028, 3, 1)), isTrue); // just after 29 Feb 2028
      expect(isDue(h, d(2028, 3, 29)), isTrue); // after EU DST change
      expect(isDue(h, d(2028, 11, 1)), isTrue); // after EU DST end
    });

    test('ignores time of day', () {
      final h = habit(schedule: EveryNDaysSchedule(2), startDate: d(2026, 3, 28));
      expect(isDue(h, DateTime(2026, 3, 30, 0, 30)), isTrue);
      expect(isDue(h, DateTime(2026, 3, 29, 23, 30)), isFalse);
    });
  });

  group('times per week', () {
    final h = habit(schedule: TimesPerWeekSchedule(2), startDate: d(2026, 1, 1));

    test('due every day without completions', () {
      for (final x in range(d(2026, 1, 1), d(2026, 1, 31))) {
        expect(isDue(h, x), isTrue);
        expect(isDue(h, x, const CompletionLog.empty()), isTrue);
      }
    });

    test('not due once the weekly target was hit on earlier days', () {
      final l = log({'h1': [d(2026, 1, 5), d(2026, 1, 7)]}); // Mon, Wed
      expect(isDue(h, d(2026, 1, 5), l), isTrue);
      expect(isDue(h, d(2026, 1, 6), l), isTrue);
      expect(isDue(h, d(2026, 1, 7), l), isTrue); // reaching day stays due
      expect(isDue(h, d(2026, 1, 8), l), isFalse);
      expect(isDue(h, d(2026, 1, 11), l), isFalse); // Sunday
      expect(isDue(h, d(2026, 1, 12), l), isTrue); // new ISO week
    });

    test('ISO week spans a year boundary', () {
      // Week of Mon 2025-12-29 .. Sun 2026-01-04.
      final h2 = habit(schedule: TimesPerWeekSchedule(1), startDate: d(2025, 12, 1));
      final l = log({'h1': [d(2025, 12, 30)]});
      expect(isDue(h2, d(2026, 1, 2), l), isFalse);
      expect(isDue(h2, d(2026, 1, 5), l), isTrue);
    });

    test('not due before startDate', () {
      expect(isDue(h, d(2025, 12, 31)), isFalse);
    });
  });

  group('dueHabitsOn / isPerfectDay', () {
    final daily = habit(id: 'daily');
    final mon = habit(id: 'mon', schedule: WeekdaysSchedule({1}));
    final archived = habit(id: 'arch', archived: true);
    final all = [daily, mon, archived];

    test('filters archived and unscheduled habits, keeps order', () {
      final none = const CompletionLog.empty();
      expect(dueHabitsOn(all, d(2026, 1, 5), none).map((h) => h.id), ['daily', 'mon']);
      expect(dueHabitsOn(all, d(2026, 1, 6), none).map((h) => h.id), ['daily']);
      expect(dueHabitsOn(all, d(2025, 6, 1), none), isEmpty);
    });

    test('perfect day needs every due habit done and at least one due', () {
      final l = log({'daily': [d(2026, 1, 5), d(2026, 1, 6)], 'mon': [d(2026, 1, 5)]});
      expect(isPerfectDay(d(2026, 1, 5), all, l), isTrue);
      expect(isPerfectDay(d(2026, 1, 6), all, l), isTrue);
      expect(isPerfectDay(d(2026, 1, 7), all, l), isFalse);
      expect(isPerfectDay(d(2026, 1, 12), all, log({'daily': [d(2026, 1, 12)]})), isFalse);
      expect(isPerfectDay(d(2026, 1, 5), [archived], l), isFalse); // nothing due
      expect(isPerfectDay(d(2026, 1, 5), const [], l), isFalse);
    });

    test('times-per-week habit already satisfied does not block a perfect day', () {
      final tpw = habit(id: 'tpw', schedule: TimesPerWeekSchedule(1));
      final l = log({'tpw': [d(2026, 1, 5)], 'daily': [d(2026, 1, 5), d(2026, 1, 6)]});
      expect(isPerfectDay(d(2026, 1, 6), [daily, tpw], l), isTrue);
      expect(isPerfectDay(d(2026, 1, 5), [daily, tpw], l), isTrue);
    });

    test('dayProgress counts done / due', () {
      final l = log({'daily': [d(2026, 1, 5)]});
      expect(dayProgress(d(2026, 1, 5), all, l), (done: 1, due: 2));
    });
  });
}
