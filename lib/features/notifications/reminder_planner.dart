/// Pure planning logic: habit → notification requests.
library;

import '../../core/utils/dates.dart';
import '../../data/models/habit.dart';
import '../../data/models/habit_schedule.dart';
import '../../domain/recurrence.dart';
import 'reminder_ids.dart';
import 'reminder_messages.dart';
import 'reminder_request.dart';

/// How many one-shot reminders are planned ahead for every-N-days habits.
/// They are topped up whenever the app starts or resumes.
const kEveryNDaysHorizon = 12;

/// Plans the notifications for [habit] as of [now] (local time).
///
/// Returns an empty list for archived habits and habits without a reminder
/// time. Every returned request fires strictly after [now] and never before
/// the habit's start date.
///
/// * Daily / times-per-week / every-1-day: one daily repeating reminder.
/// * Weekdays: one weekly repeating reminder per selected weekday
///   (slot = ISO weekday).
/// * Every N days (N ≥ 2): the next [horizon] occurrences as one-shot
///   reminders (slots 0..horizon-1).
List<ReminderRequest> planReminders(
  Habit habit, {
  required DateTime now,
  int horizon = kEveryNDaysHorizon,
}) {
  final time = habit.reminderTime;
  if (habit.archived || time == null) return const [];
  if (horizon < 1 || horizon > kReminderSlotsPerHabit) {
    throw RangeError.range(horizon, 1, kReminderSlotsPerHabit, 'horizon');
  }

  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);

  // First calendar day on which a reminder may still fire.
  final today = dateOnly(now);
  final fromDay = habit.startDate.isAfter(today) ? habit.startDate : today;

  /// First day >= [fromDay] satisfying [test] whose reminder is after now.
  DateTime? firstDay(bool Function(DateTime) test, {int maxDays = 400}) {
    for (var i = 0; i <= maxDays; i++) {
      final day = addDays(fromDay, i);
      if (test(day) && at(day).isAfter(now)) return day;
    }
    return null;
  }

  ReminderRequest request(int slot, ReminderRepeat repeat, DateTime day,
      {required int seed}) {
    return ReminderRequest(
      id: reminderId(habit.id, slot),
      habitId: habit.id,
      slot: slot,
      title: reminderTitle(habit, seed),
      body: reminderBody(seed),
      repeat: repeat,
      firstFire: at(day),
    );
  }

  List<ReminderRequest> daily() {
    final day = firstDay((_) => true)!;
    // Rotates each time the app re-plans (startup / resume).
    return [request(0, ReminderRepeat.daily, day, seed: _dayNumber(today))];
  }

  switch (habit.schedule) {
    case DailySchedule():
    case TimesPerWeekSchedule():
      return daily();
    case EveryNDaysSchedule(:final n) when n == 1:
      return daily();
    case WeekdaysSchedule(:final days):
      final sorted = days.toList()..sort();
      return [
        for (final weekday in sorted)
          request(
            weekday,
            ReminderRepeat.weekly,
            firstDay((d) => d.weekday == weekday)!,
            seed: weekday,
          ),
      ];
    case EveryNDaysSchedule(:final n):
      final first = firstDay((d) => isScheduledOn(habit, d), maxDays: n);
      if (first == null) return const [];
      final requests = <ReminderRequest>[];
      for (var slot = 0; slot < horizon; slot++) {
        final day = addDays(first, slot * n);
        requests.add(
          request(slot, ReminderRepeat.once, day, seed: _dayNumber(day)),
        );
      }
      return requests;
  }
}

/// Days since 1970-01-01 (calendar days, DST-safe).
int _dayNumber(DateTime day) => daysBetween(DateTime(1970), day);
