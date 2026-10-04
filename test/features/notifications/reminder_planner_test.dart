import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/features/notifications/reminder_ids.dart';
import 'package:habit_quest/features/notifications/reminder_messages.dart';
import 'package:habit_quest/features/notifications/reminder_planner.dart';
import 'package:habit_quest/features/notifications/reminder_request.dart';

import 'notification_test_helpers.dart';

void main() {
  // Monday 2026-01-05, 07:00.
  final morning = DateTime(2026, 1, 5, 7);
  // Same day, after the 08:30 reminder.
  final evening = DateTime(2026, 1, 5, 20);

  group('no reminders', () {
    test('without a reminder time', () {
      expect(planReminders(reminderHabit(reminderTime: null), now: morning),
          isEmpty);
    });

    test('for archived habits', () {
      expect(planReminders(reminderHabit(archived: true), now: morning),
          isEmpty);
    });
  });

  group('daily', () {
    test('one daily repeating reminder today when still ahead', () {
      final plan = planReminders(reminderHabit(), now: morning);
      expect(plan, hasLength(1));
      final r = plan.single;
      expect(r.repeat, ReminderRepeat.daily);
      expect(r.firstFire, DateTime(2026, 1, 5, 8, 30));
      expect(r.slot, 0);
      expect(r.id, reminderId('h1', 0));
      expect(r.habitId, 'h1');
    });

    test('starts tomorrow when today\'s time has passed', () {
      final r = planReminders(reminderHabit(), now: evening).single;
      expect(r.firstFire, DateTime(2026, 1, 6, 8, 30));
    });

    test('exactly at the reminder time counts as passed', () {
      final r = planReminders(reminderHabit(),
              now: DateTime(2026, 1, 5, 8, 30))
          .single;
      expect(r.firstFire, DateTime(2026, 1, 6, 8, 30));
    });

    test('never before the start date', () {
      final r = planReminders(reminderHabit(startDate: DateTime(2026, 2, 1)),
              now: morning)
          .single;
      expect(r.firstFire, DateTime(2026, 2, 1, 8, 30));
    });

    test('every 1 day behaves like daily', () {
      final plan = planReminders(
          reminderHabit(schedule: EveryNDaysSchedule(1)),
          now: morning);
      expect(plan.single.repeat, ReminderRepeat.daily);
    });
  });

  group('times per week', () {
    test('is a daily reminder', () {
      final plan = planReminders(
          reminderHabit(schedule: TimesPerWeekSchedule(3)),
          now: morning);
      expect(plan.single.repeat, ReminderRepeat.daily);
      expect(plan.single.firstFire, DateTime(2026, 1, 5, 8, 30));
    });
  });

  group('weekdays', () {
    test('one weekly reminder per weekday, slot = ISO weekday', () {
      final plan = planReminders(
        reminderHabit(schedule: WeekdaysSchedule({5, 1, 3})),
        now: morning, // Monday 07:00
      );
      expect(plan.map((r) => r.repeat).toSet(), {ReminderRepeat.weekly});
      expect(plan.map((r) => r.slot), [1, 3, 5]);
      expect(plan.map((r) => r.weekday), [1, 3, 5]);
      expect(plan.map((r) => r.firstFire), [
        DateTime(2026, 1, 5, 8, 30), // today
        DateTime(2026, 1, 7, 8, 30),
        DateTime(2026, 1, 9, 8, 30),
      ]);
      expect(plan.map((r) => r.id).toSet(), hasLength(3));
    });

    test('today\'s weekday moves to next week once passed', () {
      final plan = planReminders(
        reminderHabit(schedule: WeekdaysSchedule({1})),
        now: evening,
      );
      expect(plan.single.firstFire, DateTime(2026, 1, 12, 8, 30));
    });
  });

  group('every N days', () {
    test('plans the next occurrences as one-shots', () {
      // Start 2026-01-01, every 3 days → 1, 4, 7, 10, …
      final plan = planReminders(
        reminderHabit(schedule: EveryNDaysSchedule(3)),
        now: morning, // Jan 5
      );
      expect(plan, hasLength(kEveryNDaysHorizon));
      expect(plan.map((r) => r.repeat).toSet(), {ReminderRepeat.once});
      expect(plan.map((r) => r.slot),
          List.generate(kEveryNDaysHorizon, (i) => i));
      expect(plan.first.firstFire, DateTime(2026, 1, 7, 8, 30));
      expect(plan[1].firstFire, DateTime(2026, 1, 10, 8, 30));
      expect(plan.last.firstFire, DateTime(2026, 2, 9, 8, 30));
    });

    test('includes today when the reminder is still ahead', () {
      final plan = planReminders(
        reminderHabit(schedule: EveryNDaysSchedule(2)),
        now: DateTime(2026, 1, 3, 6), // Jan 3 is scheduled (1, 3, 5…)
      );
      expect(plan.first.firstFire, DateTime(2026, 1, 3, 8, 30));
    });

    test('skips today when the reminder has passed', () {
      final plan = planReminders(
        reminderHabit(schedule: EveryNDaysSchedule(2)),
        now: DateTime(2026, 1, 3, 9),
      );
      expect(plan.first.firstFire, DateTime(2026, 1, 5, 8, 30));
    });

    test('future start date is the first occurrence', () {
      final plan = planReminders(
        reminderHabit(
            schedule: EveryNDaysSchedule(7), startDate: DateTime(2026, 3, 1)),
        now: morning,
      );
      expect(plan.first.firstFire, DateTime(2026, 3, 1, 8, 30));
      expect(plan[1].firstFire, DateTime(2026, 3, 8, 8, 30));
    });

    test('custom horizon', () {
      final plan = planReminders(
        reminderHabit(schedule: EveryNDaysSchedule(2)),
        now: morning,
        horizon: 5,
      );
      expect(plan, hasLength(5));
    });

    test('occurrences survive a DST change (local wall clock)', () {
      // Europe/US DST shifts happen in March; dates stay calendar-correct.
      final plan = planReminders(
        reminderHabit(
            schedule: EveryNDaysSchedule(2), startDate: DateTime(2026, 3, 1)),
        now: DateTime(2026, 3, 1),
      );
      for (final r in plan) {
        expect(r.hour, 8);
        expect(r.minute, 30);
      }
      expect(plan[7].firstFire, DateTime(2026, 3, 15, 8, 30));
    });
  });

  group('messages', () {
    test('fill in emoji and name', () {
      final habit = reminderHabit(name: 'Read', emoji: '📚');
      for (var seed = 0; seed < kReminderTemplates.length; seed++) {
        final title = reminderTitle(habit, seed);
        expect(title, contains('📚 Read'));
        expect(title, isNot(contains('{')));
      }
    });

    test('rotate deterministically with the seed', () {
      final habit = reminderHabit();
      expect(kReminderTemplates, hasLength(8));
      final titles = {
        for (var seed = 0; seed < 8; seed++) reminderTitle(habit, seed),
      };
      expect(titles, hasLength(8));
      expect(reminderTitle(habit, 3), reminderTitle(habit, 11));
      expect(reminderTitle(habit, -3), reminderTitle(habit, 3));
    });

    test('weekly slots get different messages', () {
      final plan = planReminders(
        reminderHabit(schedule: WeekdaysSchedule({1, 2, 3})),
        now: morning,
      );
      expect(plan.map((r) => r.title).toSet(), hasLength(3));
    });

    test('planning is deterministic', () {
      Habit h() => reminderHabit(schedule: EveryNDaysSchedule(3));
      expect(planReminders(h(), now: morning), planReminders(h(), now: morning));
    });
  });
}
