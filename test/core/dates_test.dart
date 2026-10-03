import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/utils/dates.dart';

void main() {
  test('dateOnly strips time and maps UTC to the same calendar day', () {
    expect(dateOnly(DateTime(2026, 3, 29, 23, 59)), DateTime(2026, 3, 29));
    expect(dateOnly(DateTime.utc(2026, 3, 29, 12)), DateTime(2026, 3, 29));
    expect(dateOnly(DateTime.utc(2026, 3, 29)).isUtc, isFalse);
  });

  test('addDays crosses month, year and leap-day boundaries', () {
    expect(addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
    expect(addDays(DateTime(2025, 12, 31), 1), DateTime(2026, 1, 1));
    expect(addDays(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 31));
    expect(addDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
    expect(addDays(DateTime(2026, 2, 28), 1), DateTime(2026, 3, 1));
  });

  test('addDays and daysBetween are DST-safe (EU and US transitions)', () {
    // Walk a whole year day by day: always midnight, always +1 day.
    var x = DateTime(2026, 1, 1);
    for (var i = 0; i < 400; i++) {
      final next = addDays(x, 1);
      expect(next.hour, 0);
      expect(daysBetween(x, next), 1);
      x = next;
    }
    expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(daysBetween(DateTime(2026, 11, 1, 23), DateTime(2026, 11, 2)), 1);
    expect(daysBetween(DateTime(2026, 1, 10), DateTime(2026, 1, 1)), -9);
  });

  test('ISO week helpers', () {
    // 2026-01-01 is a Thursday.
    expect(startOfIsoWeek(DateTime(2026, 1, 1)), DateTime(2025, 12, 29));
    expect(endOfIsoWeek(DateTime(2026, 1, 1)), DateTime(2026, 1, 4));
    expect(startOfIsoWeek(DateTime(2026, 1, 5)), DateTime(2026, 1, 5));
    expect(startOfIsoWeek(DateTime(2026, 1, 11)), DateTime(2026, 1, 5));
  });

  test('month helpers', () {
    expect(daysInMonth(DateTime(2028, 2, 10)), 29);
    expect(daysInMonth(DateTime(2026, 2, 10)), 28);
    expect(daysInMonth(DateTime(2026, 12, 10)), 31);
    expect(startOfMonth(DateTime(2026, 7, 19)), DateTime(2026, 7, 1));
  });

  test('dateKey round-trips', () {
    expect(dateKey(DateTime(2026, 3, 5, 14)), '2026-03-05');
    expect(parseDateKey('2026-03-05'), DateTime(2026, 3, 5));
    expect(() => parseDateKey('nope'), throwsFormatException);
    expect(isSameDay(DateTime(2026, 3, 5, 1), DateTime(2026, 3, 5, 23)), isTrue);
  });
}
