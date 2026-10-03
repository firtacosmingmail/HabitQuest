import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';

import '../helpers/fixtures.dart';

void main() {
  group('HabitSchedule', () {
    final schedules = <HabitSchedule>[
      const DailySchedule(),
      WeekdaysSchedule({1, 3, 5}),
      EveryNDaysSchedule(3),
      TimesPerWeekSchedule(4),
    ];

    for (final s in schedules) {
      test('JSON round-trip: $s', () {
        final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
        expect(HabitSchedule.fromJson(json), s);
      });
    }

    test('validation', () {
      expect(() => WeekdaysSchedule({}), throwsArgumentError);
      expect(() => WeekdaysSchedule({0}), throwsArgumentError);
      expect(() => WeekdaysSchedule({8}), throwsArgumentError);
      expect(() => EveryNDaysSchedule(0), throwsArgumentError);
      expect(() => TimesPerWeekSchedule(0), throwsArgumentError);
      expect(() => TimesPerWeekSchedule(8), throwsArgumentError);
      expect(() => HabitSchedule.fromJson({'type': 'x'}), throwsFormatException);
    });

    test('weekday equality ignores order', () {
      expect(WeekdaysSchedule({5, 1}), WeekdaysSchedule({1, 5}));
      expect(WeekdaysSchedule({5, 1}).hashCode, WeekdaysSchedule({1, 5}).hashCode);
    });
  });

  group('Habit', () {
    test('JSON round-trip with and without reminder', () {
      final h = Habit(
        id: 'a',
        name: 'Read',
        emoji: '📚',
        colorValue: 0xFF7C4DFF,
        schedule: WeekdaysSchedule({2, 4}),
        reminderTime: const ReminderTime(hour: 7, minute: 30),
        createdAt: DateTime(2026, 1, 2, 9, 15),
        startDate: DateTime(2026, 1, 3, 18),
        archived: true,
      );
      final back = Habit.fromJson(
        jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>,
      );
      expect(back, h);
      expect(back.startDate, DateTime(2026, 1, 3));

      final noReminder = h.copyWith(clearReminderTime: true);
      expect(noReminder.reminderTime, isNull);
      expect(
        Habit.fromJson(jsonDecode(jsonEncode(noReminder.toJson()))),
        noReminder,
      );
    });

    test('copyWith keeps id and createdAt', () {
      final h = habit();
      final c = h.copyWith(name: 'New', archived: true);
      expect(c.id, h.id);
      expect(c.createdAt, h.createdAt);
      expect(c.name, 'New');
      expect(c.archived, isTrue);
      expect(c.schedule, h.schedule);
    });
  });

  group('CompletionLog', () {
    test('queries', () {
      final l = log({
        'a': [d(2026, 1, 1), d(2026, 1, 3), d(2026, 1, 3)],
        'b': [],
      });
      expect(l.isCompleted('a', DateTime(2026, 1, 3, 22)), isTrue);
      expect(l.isCompleted('a', d(2026, 1, 2)), isFalse);
      expect(l.isCompleted('b', d(2026, 1, 1)), isFalse);
      expect(l.totalFor('a'), 2);
      expect(l.datesFor('a'), [d(2026, 1, 1), d(2026, 1, 3)]);
      expect(l.countInRange('a', d(2026, 1, 2), d(2026, 1, 3)), 1);
      expect(l.habitIds, ['a']);
    });

    test('withCompletion is immutable', () {
      const empty = CompletionLog.empty();
      final l = empty.withCompletion('a', d(2026, 1, 1), true);
      expect(empty.isCompleted('a', d(2026, 1, 1)), isFalse);
      expect(l.isCompleted('a', d(2026, 1, 1)), isTrue);
      expect(l.withCompletion('a', d(2026, 1, 1), false), empty);
      expect(l, log({'a': [d(2026, 1, 1)]}));
    });
  });
}
