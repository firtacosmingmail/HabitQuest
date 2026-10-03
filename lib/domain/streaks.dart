/// Pure streak calculation, counted in *scheduled periods*.
///
/// * Day-based schedules (daily, weekdays, every N days): one period per
///   scheduled day. Days on which the habit is not scheduled never break a
///   streak, and check-ins on non-scheduled days do not extend it.
/// * [TimesPerWeekSchedule]: one period per ISO week (Mon–Sun). A week is
///   successful when it has at least `times` check-ins. The week containing
///   the start date only needs `min(times, days left in that week)`.
/// * The period in progress (today / the current week) extends the current
///   streak once it is complete, but never breaks it while it is not.
/// * Check-ins before `startDate` or after `today` are ignored.
library;

import 'dart:math' as math;

import '../core/utils/dates.dart';
import '../data/models/completion_log.dart';
import '../data/models/habit.dart';
import '../data/models/habit_schedule.dart';
import 'recurrence.dart';

/// The unit a habit's streak is counted in.
enum StreakUnit { days, weeks }

StreakUnit streakUnitOf(Habit habit) => habit.schedule is TimesPerWeekSchedule
    ? StreakUnit.weeks
    : StreakUnit.days;

/// Current and best streak for one habit.
class StreakInfo {
  final int current;
  final int best;
  final StreakUnit unit;

  const StreakInfo({
    required this.current,
    required this.best,
    required this.unit,
  });

  @override
  bool operator ==(Object other) =>
      other is StreakInfo &&
      other.current == current &&
      other.best == best &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(current, best, unit);

  @override
  String toString() => 'StreakInfo(current: $current, best: $best, $unit)';
}

/// Current streak of [habit] as of [today] (in [streakUnitOf] units).
int currentStreak(Habit habit, CompletionLog completions, DateTime today) {
  final t = dateOnly(today);
  if (t.isBefore(habit.startDate)) return 0;
  if (habit.schedule case TimesPerWeekSchedule(:final times)) {
    var week = startOfIsoWeek(t);
    var count = 0;
    // Current week: counts if already successful, never breaks.
    if (_weekSucceeded(habit, completions, week, times, t)) count++;
    week = addDays(week, -7);
    while (!endOfIsoWeek(week).isBefore(habit.startDate) &&
        _weekSucceeded(habit, completions, week, times, t)) {
      count++;
      week = addDays(week, -7);
    }
    return count;
  }

  var count = 0;
  var day = t;
  // Today: counts if done, never breaks.
  if (isScheduledOn(habit, day) && completions.isCompleted(habit.id, day)) {
    count++;
  }
  day = addDays(day, -1);
  while (!day.isBefore(habit.startDate)) {
    if (isScheduledOn(habit, day)) {
      if (!completions.isCompleted(habit.id, day)) break;
      count++;
    }
    day = addDays(day, -1);
  }
  return count;
}

/// Longest streak of [habit] up to and including [today].
int bestStreak(Habit habit, CompletionLog completions, DateTime today) {
  final t = dateOnly(today);
  final dates = completions
      .datesFor(habit.id)
      .where((d) => !d.isBefore(habit.startDate) && !d.isAfter(t))
      .toList();
  if (dates.isEmpty) return 0;

  var best = 0;
  var run = 0;
  if (habit.schedule case TimesPerWeekSchedule(:final times)) {
    for (var week = startOfIsoWeek(dates.first);
        !week.isAfter(t);
        week = addDays(week, 7)) {
      if (_weekSucceeded(habit, completions, week, times, t)) {
        run++;
        best = math.max(best, run);
      } else {
        run = 0;
      }
    }
    return best;
  }

  for (var day = dates.first; !day.isAfter(t); day = addDays(day, 1)) {
    if (!isScheduledOn(habit, day)) continue;
    if (completions.isCompleted(habit.id, day)) {
      run++;
      best = math.max(best, run);
    } else {
      run = 0;
    }
  }
  return best;
}

/// Both streaks at once.
StreakInfo streakInfo(Habit habit, CompletionLog completions, DateTime today) =>
    StreakInfo(
      current: currentStreak(habit, completions, today),
      best: bestStreak(habit, completions, today),
      unit: streakUnitOf(habit),
    );

bool _weekSucceeded(
  Habit habit,
  CompletionLog completions,
  DateTime weekStart,
  int times,
  DateTime today,
) {
  final from = weekStart.isBefore(habit.startDate) ? habit.startDate : weekStart;
  final weekEnd = addDays(weekStart, 6);
  final to = weekEnd.isAfter(today) ? today : weekEnd;
  if (to.isBefore(from)) return false;
  final available = daysBetween(from, weekEnd) + 1;
  final required = math.min(times, available);
  return completions.countInRange(habit.id, from, to) >= required;
}
