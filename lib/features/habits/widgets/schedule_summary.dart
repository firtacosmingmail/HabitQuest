/// Human-readable schedule text, e.g. "Every day", "Mon · Wed · Fri",
/// "Every 3 days", "3× per week". Pure Dart, reusable by any screen.
library;

import '../../../core/constants/habit_defaults.dart';
import '../../../core/utils/dates.dart';
import '../../../data/models/completion_log.dart';
import '../../../data/models/habit.dart';
import '../../../data/models/habit_schedule.dart';

/// Short summary of [schedule].
String scheduleSummary(HabitSchedule schedule) => switch (schedule) {
  DailySchedule() => 'Every day',
  WeekdaysSchedule(:final days) => weekdaysSummary(days),
  EveryNDaysSchedule(:final n) => n == 1 ? 'Every day' : 'Every $n days',
  TimesPerWeekSchedule(:final times) => '$times× per week',
};

/// "Mon · Wed · Fri"; all seven days → "Every day", Mon–Fri → "Weekdays",
/// Sat+Sun → "Weekends".
String weekdaysSummary(Set<int> days) {
  final sorted = days.toList()..sort();
  if (sorted.length == 7) return 'Every day';
  if (sorted.length == 5 && sorted.first == 1 && sorted.last == 5) {
    return 'Weekdays';
  }
  if (sorted.length == 2 && sorted.first == 6 && sorted.last == 7) {
    return 'Weekends';
  }
  return sorted.map((d) => HabitDefaults.weekdayShort[d]).join(' · ');
}

/// Check-ins this ISO week vs. the weekly target, for times-per-week habits
/// (`null` for other schedules).
({int done, int target})? weeklyProgress(
  Habit habit,
  CompletionLog log,
  DateTime today,
) {
  final schedule = habit.schedule;
  if (schedule is! TimesPerWeekSchedule) return null;
  final t = dateOnly(today);
  return (
    done: log.countInRange(habit.id, startOfIsoWeek(t), t),
    target: schedule.times,
  );
}

/// [scheduleSummary] plus the weekly progress when available, e.g.
/// "3× per week · 1/3 this week".
String scheduleSummaryWithProgress(
  HabitSchedule schedule, [
  ({int done, int target})? progress,
]) {
  final base = scheduleSummary(schedule);
  if (progress == null) return base;
  return '$base · ${progress.done}/${progress.target} this week';
}
