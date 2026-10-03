/// Pure completion-rate calculation for the habit details screen.
library;

import 'dart:math' as math;

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../data/models/habit_schedule.dart';
import '../../domain/recurrence.dart';
import '../../domain/streaks.dart';

/// How many scheduled periods (days, or weeks for times-per-week habits)
/// were completed out of how many were scheduled.
class CompletionRate {
  final int completed;
  final int total;
  final StreakUnit unit;

  const CompletionRate({
    required this.completed,
    required this.total,
    required this.unit,
  });

  /// `completed / total`, or `null` when nothing has been scheduled yet.
  double? get ratio => total == 0 ? null : completed / total;

  /// Rounded percentage (0..100), or `null` when nothing is scheduled yet.
  int? get percent {
    final r = ratio;
    return r == null ? null : (r * 100).round();
  }

  @override
  bool operator ==(Object other) =>
      other is CompletionRate &&
      other.completed == completed &&
      other.total == total &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(completed, total, unit);

  @override
  String toString() => 'CompletionRate($completed / $total $unit)';
}

/// Completion rate of [habit] from its start date up to [today].
///
/// * Day schedules (daily, weekdays, every N days): completed scheduled days
///   divided by scheduled days. Check-ins on non-scheduled days are ignored.
/// * [TimesPerWeekSchedule]: successful ISO weeks divided by weeks. The week
///   containing the start date only needs `min(times, days left)` check-ins
///   (same rule as the streaks).
/// * The period in progress (today, or the current week) is only counted
///   once it is complete, so an unfinished today never lowers the rate.
CompletionRate completionRate(
  Habit habit,
  CompletionLog completions,
  DateTime today,
) {
  final t = dateOnly(today);
  final start = habit.startDate;
  final unit = streakUnitOf(habit);
  var completed = 0;
  var total = 0;

  if (t.isBefore(start)) {
    return CompletionRate(completed: 0, total: 0, unit: unit);
  }

  if (habit.schedule case TimesPerWeekSchedule(:final times)) {
    final currentWeek = startOfIsoWeek(t);
    for (var week = startOfIsoWeek(start);
        !week.isAfter(currentWeek);
        week = addDays(week, 7)) {
      final from = week.isBefore(start) ? start : week;
      final weekEnd = addDays(week, 6);
      final to = weekEnd.isAfter(t) ? t : weekEnd;
      final required = math.min(times, daysBetween(from, weekEnd) + 1);
      final succeeded = completions.countInRange(habit.id, from, to) >= required;
      if (week == currentWeek && !succeeded) continue;
      total++;
      if (succeeded) completed++;
    }
    return CompletionRate(completed: completed, total: total, unit: unit);
  }

  for (var day = start; !day.isAfter(t); day = addDays(day, 1)) {
    if (!isScheduledOn(habit, day)) continue;
    final done = completions.isCompleted(habit.id, day);
    if (day == t && !done) continue;
    total++;
    if (done) completed++;
  }
  return CompletionRate(completed: completed, total: total, unit: unit);
}
