/// Pure recurrence engine: when is a habit due?
///
/// All functions normalise their date arguments with `dateOnly`, so any
/// `DateTime` (with a time of day, UTC or local) is accepted.
library;

import '../core/utils/dates.dart';
import '../data/models/completion_log.dart';
import '../data/models/habit.dart';
import '../data/models/habit_schedule.dart';

/// Whether [date] is a *scheduled* day for [habit], ignoring check-ins and
/// the archived flag. Never true before `habit.startDate`.
///
/// For [TimesPerWeekSchedule] every day from the start date is a candidate
/// day; use [isDue] to account for the weekly target.
bool isScheduledOn(Habit habit, DateTime date) {
  final d = dateOnly(date);
  if (d.isBefore(habit.startDate)) return false;
  return switch (habit.schedule) {
    DailySchedule() => true,
    WeekdaysSchedule(:final days) => days.contains(d.weekday),
    EveryNDaysSchedule(:final n) => daysBetween(habit.startDate, d) % n == 0,
    TimesPerWeekSchedule() => true,
  };
}

/// Whether [habit] is due on [date].
///
/// Same as [isScheduledOn], except for [TimesPerWeekSchedule]: the habit is
/// due on a day only while the week's target has not been reached by
/// check-ins on *earlier* days of the same ISO week (Mon–Sun). A day that
/// itself holds the check-in reaching the target therefore stays due (and
/// completed). Without [completions] a times-per-week habit is due every day.
///
/// Does not look at `habit.archived`; [dueHabitsOn] filters archived habits.
bool isDue(Habit habit, DateTime date, [CompletionLog? completions]) {
  final d = dateOnly(date);
  if (!isScheduledOn(habit, d)) return false;
  final schedule = habit.schedule;
  if (schedule is TimesPerWeekSchedule && completions != null) {
    final weekStart = startOfIsoWeek(d);
    if (d == weekStart) return true;
    final before = completions.countInRange(habit.id, weekStart, addDays(d, -1));
    return before < schedule.times;
  }
  return true;
}

/// Non-archived habits due on [date], preserving input order.
List<Habit> dueHabitsOn(
  Iterable<Habit> habits,
  DateTime date,
  CompletionLog completions,
) =>
    habits
        .where((h) => !h.archived && isDue(h, date, completions))
        .toList(growable: false);

/// A Perfect Day: at least one non-archived habit is due on [date] and every
/// due habit is checked in on that day.
bool isPerfectDay(
  DateTime date,
  Iterable<Habit> habits,
  CompletionLog completions,
) {
  final due = dueHabitsOn(habits, date, completions);
  return due.isNotEmpty &&
      due.every((h) => completions.isCompleted(h.id, date));
}

/// Progress for a single day: how many due habits are done.
({int done, int due}) dayProgress(
  DateTime date,
  Iterable<Habit> habits,
  CompletionLog completions,
) {
  final due = dueHabitsOn(habits, date, completions);
  final done = due.where((h) => completions.isCompleted(h.id, date)).length;
  return (done: done, due: due.length);
}
