import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/calendar/calendar_month.dart';

import '../../helpers/fixtures.dart';

void main() {
  group('monthGridDays', () {
    test('pads to Monday-first full weeks', () {
      final cells = monthGridDays(d(2026, 10, 15)); // Oct 1 = Thursday
      expect(cells.length, 35);
      expect(cells.take(3), everyElement(isNull));
      expect(cells[3], d(2026, 10, 1));
      expect(cells[33], d(2026, 10, 31));
      expect(cells[34], isNull);
    });

    test('month starting on Monday has no leading padding', () {
      final cells = monthGridDays(d(2026, 6, 1)); // Jun 1 2026 = Monday
      expect(cells.first, d(2026, 6, 1));
      expect(cells.length % 7, 0);
    });

    test('February that needs four rows', () {
      final cells = monthGridDays(d(2027, 2, 1)); // Feb 1 2027 = Monday
      expect(cells.length, 28);
      expect(cells.whereType<DateTime>().length, 28);
    });
  });

  group('dayStatus / perfectDaysInMonth', () {
    final habits = [habit(id: 'a', startDate: d(2026, 10, 5))];
    final completions = log({
      'a': [d(2026, 10, 5), d(2026, 10, 6), d(2026, 10, 20)],
    });
    final today = d(2026, 10, 15);

    test('classifies empty, tracked and upcoming days', () {
      expect(dayStatus(d(2026, 10, 4), today, habits, completions).kind,
          DayKind.empty);
      final done = dayStatus(d(2026, 10, 5), today, habits, completions);
      expect((done.kind, done.done, done.due, done.isPerfect),
          (DayKind.tracked, 1, 1, true));
      final missed = dayStatus(d(2026, 10, 7), today, habits, completions);
      expect((missed.done, missed.isPerfect), (0, false));
      final future = dayStatus(d(2026, 10, 20), today, habits, completions);
      expect((future.kind, future.done, future.isPerfect),
          (DayKind.upcoming, 0, false));
    });

    test('counts Perfect Days up to today only', () {
      expect(perfectDaysInMonth(d(2026, 10, 1), today, habits, completions), 2);
    });
  });
}
