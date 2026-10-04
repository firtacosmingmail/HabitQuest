import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/notifications/reminder_ids.dart';

void main() {
  test('ids are stable for the same habit and slot', () {
    expect(reminderId('abc', 3), reminderId('abc', 3));
    // Known value guards against accidental changes of the hash.
    expect(stableHash(''), 0x811C9DC5);
    expect(stableHash('a'), 0xE40C292C);
  });

  test('slots of one habit are distinct and contiguous', () {
    final ids = allReminderIds('habit-1');
    expect(ids, hasLength(kReminderSlotsPerHabit));
    expect(ids.toSet(), hasLength(kReminderSlotsPerHabit));
    for (var i = 1; i < ids.length; i++) {
      expect(ids[i], ids[0] + i);
    }
  });

  test('ids fit in a positive 32-bit int', () {
    for (final id in ['a', 'zzzz', 'f47ac10b-58cc-4372-a567-0e02b2c3d479']) {
      for (final rid in allReminderIds(id)) {
        expect(rid, inInclusiveRange(0, 0x7FFFFFFF));
      }
    }
  });

  test('different habits get disjoint id ranges', () {
    final a = allReminderIds('f47ac10b-58cc-4372-a567-0e02b2c3d479').toSet();
    final b = allReminderIds('9b2e7c1a-1111-4c2b-9f00-123456789abc').toSet();
    expect(a.intersection(b), isEmpty);
  });

  test('slot out of range throws', () {
    expect(() => reminderId('x', -1), throwsRangeError);
    expect(() => reminderId('x', kReminderSlotsPerHabit), throwsRangeError);
  });
}
