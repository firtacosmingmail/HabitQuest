/// Pure helpers for laying out and summarising a calendar month.
library;

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../domain/recurrence.dart';

/// The cells of a Monday-first month grid for [month]: `null` for the
/// padding before the 1st and after the last day, so the length is a
/// multiple of 7.
List<DateTime?> monthGridDays(DateTime month) {
  final first = startOfMonth(month);
  final leading = first.weekday - DateTime.monday;
  final days = daysInMonth(first);
  final total = ((leading + days + 6) ~/ 7) * 7;
  return [
    for (var i = 0; i < total; i++)
      (i < leading || i >= leading + days) ? null : addDays(first, i - leading),
  ];
}

/// How a single calendar day should look.
enum DayKind {
  /// Nothing due: a plain day.
  empty,

  /// Today or earlier with at least one habit due.
  tracked,

  /// After today with at least one habit due (shown faintly, no progress).
  upcoming,
}

/// Everything a day cell needs to draw itself.
class DayStatus {
  final DateTime date;
  final int done;
  final int due;
  final DayKind kind;

  const DayStatus({
    required this.date,
    required this.done,
    required this.due,
    required this.kind,
  });

  bool get isPerfect => kind == DayKind.tracked && due > 0 && done == due;

  double get fraction => due == 0 ? 0 : done / due;
}

/// Computes the [DayStatus] for [date] relative to [today].
DayStatus dayStatus(
  DateTime date,
  DateTime today,
  Iterable<Habit> habits,
  CompletionLog log,
) {
  final d = dateOnly(date);
  final p = dayProgress(d, habits, log);
  final DayKind kind;
  if (p.due == 0) {
    kind = DayKind.empty;
  } else if (d.isAfter(today)) {
    kind = DayKind.upcoming;
  } else {
    kind = DayKind.tracked;
  }
  return DayStatus(
    date: d,
    done: kind == DayKind.upcoming ? 0 : p.done,
    due: p.due,
    kind: kind,
  );
}

/// Number of Perfect Days in [month] up to and including [today].
int perfectDaysInMonth(
  DateTime month,
  DateTime today,
  Iterable<Habit> habits,
  CompletionLog log,
) {
  final first = startOfMonth(month);
  var count = 0;
  for (var i = 0; i < daysInMonth(first); i++) {
    final day = addDays(first, i);
    if (day.isAfter(today)) break;
    if (isPerfectDay(day, habits, log)) count++;
  }
  return count;
}
