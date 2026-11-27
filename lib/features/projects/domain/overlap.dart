/// Pure overlap detection between time blocks (of all projects).
///
/// Rule (see docs/PROJECTS.md "Overlap"): two blocks overlap when, on some
/// calendar day, both have a session and their wall-clock intervals
/// `[start, end)` intersect. Touching ends (10:00–13:00 and 13:00–15:00)
/// do NOT overlap. Deleted blocks and blocks of deleted projects are
/// ignored; archived projects still count.
///
/// Blocks may be open-ended (no end date), so the search cannot rely on a
/// short horizon. It uses the periodicity of the patterns instead:
/// * weekly × weekly repeats every 7 days, so 7 days from the common start
///   decide it;
/// * anything with a monthly pattern is scanned month by month (only the
///   candidate days of each month are looked at) for at most one full
///   Gregorian cycle (400 years = 146 097 days = 20 871 weeks, after which
///   weekdays and month days repeat exactly). In practice the first clash
///   is found within a few months; "never" is decided upfront when the
///   day sets cannot meet (e.g. the 30th vs the 31st).
library;

import '../../../core/utils/dates.dart';
import '../models/clock_time.dart';
import '../models/project.dart';
import '../models/projects_data.dart';
import '../models/time_block.dart';

/// Another time block that clashes with a candidate block.
class TimeBlockClash {
  /// The existing, clashing block.
  final TimeBlock block;

  /// Its project (`null` only if the snapshot lacks it).
  final Project? project;

  /// The first calendar day on which both have overlapping sessions.
  final DateTime firstDate;

  const TimeBlockClash({
    required this.block,
    required this.project,
    required this.firstDate,
  });

  /// e.g. `"Content business" (Editing), Mon–Fri 10:00–13:00, first on 2026-11-16`.
  String describe() {
    final name = '"${project?.name ?? 'Unknown project'}"';
    final where = block.label == null ? name : '$name (${block.label})';
    return '$where, ${describeRecurrence(block.recurrence)} '
        '${block.startTime}–${block.endTime}, '
        'first on ${dateKey(firstDate)}';
  }

  @override
  String toString() => 'TimeBlockClash(${block.id}, ${dateKey(firstDate)})';
}

/// Thrown by `ProjectService` when saving a time block would overlap
/// other blocks. Nothing is saved.
class TimeBlockOverlapException implements Exception {
  /// The block that was being saved.
  final TimeBlock block;

  /// Every clashing block, sorted by [TimeBlockClash.firstDate].
  final List<TimeBlockClash> clashes;

  const TimeBlockOverlapException(this.block, this.clashes);

  /// A user-facing English message naming the clashing projects, labels
  /// and times.
  String get message {
    final head = 'This time block (${describeRecurrence(block.recurrence)} '
        '${block.startTime}–${block.endTime}) overlaps ';
    return head + clashes.map((c) => c.describe()).join('; ');
  }

  @override
  String toString() => 'TimeBlockOverlapException: $message';
}

/// Whether two wall-clock intervals `[aStart, aEnd)` and `[bStart, bEnd)`
/// intersect (touching ends do not).
bool timesOverlap(ClockTime aStart, ClockTime aEnd, ClockTime bStart,
        ClockTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// Months in one Gregorian cycle (400 years): weekday/day-of-month
/// combinations repeat exactly after it.
const _gregorianCycleMonths = 400 * 12;

/// The first calendar day on which [a] and [b] both have a session and
/// their times intersect, or `null` if that never happens (open-ended
/// blocks included).
DateTime? firstOverlapDate(TimeBlock a, TimeBlock b) {
  if (!timesOverlap(a.startTime, a.endTime, b.startTime, b.endTime)) {
    return null;
  }
  final from = a.effectiveStartDate.isAfter(b.effectiveStartDate)
      ? a.effectiveStartDate
      : b.effectiveStartDate;
  final ae = a.endDate, be = b.endDate;
  final DateTime? to = ae == null
      ? be
      : (be == null ? ae : (ae.isBefore(be) ? ae : be));
  if (to != null && to.isBefore(from)) return null;
  return firstCommonDay(a.recurrence, b.recurrence, from: from, to: to);
}

/// The first day `d` in `[from, to]` (`to == null`: no end) on which both
/// patterns occur, or `null`. See the library doc for the bounds.
DateTime? firstCommonDay(
  BlockRecurrence a,
  BlockRecurrence b, {
  required DateTime from,
  DateTime? to,
}) {
  final start = dateOnly(from);
  final end = to == null ? null : dateOnly(to);
  bool inRange(DateTime d) =>
      !d.isBefore(start) && (end == null || !d.isAfter(end));

  switch ((a, b)) {
    case (WeeklyRecurrence(weekdays: final x),
          WeeklyRecurrence(weekdays: final y)):
      if (!x.any(y.contains)) return null;
      for (var i = 0; i < 7; i++) {
        final d = addDays(start, i);
        if (!inRange(d)) return null;
        if (x.contains(d.weekday) && y.contains(d.weekday)) return d;
      }
      return null;
    case (MonthlyRecurrence(monthDays: final x),
          MonthlyRecurrence(monthDays: final y)):
      final days = (x.where(y.contains).toList()..sort());
      if (days.isEmpty) return null;
      return _scanMonths(start, end, (year, month, len, _) sync* {
        for (final d in days) {
          if (d <= len) yield d;
        }
      });
    case (WeeklyRecurrence(weekdays: final w),
          MonthlyRecurrence(monthDays: final m)):
    case (MonthlyRecurrence(monthDays: final m),
          WeeklyRecurrence(weekdays: final w)):
      final days = m.toList()..sort();
      return _scanMonths(start, end, (year, month, len, firstWeekday) sync* {
        for (final d in days) {
          if (d > len) break;
          final weekday = (firstWeekday - 1 + d - 1) % 7 + 1;
          if (w.contains(weekday)) yield d;
        }
      });
  }
}

/// Walks months from [start]'s month; [candidates] yields the matching
/// days of a month ascending (`len` = days in the month, `firstWeekday` =
/// ISO weekday of its 1st). Returns the first candidate within
/// `[start, end]`, or `null` after [end] or one Gregorian cycle.
DateTime? _scanMonths(
  DateTime start,
  DateTime? end,
  Iterable<int> Function(int year, int month, int len, int firstWeekday)
      candidates,
) {
  var year = start.year, month = start.month;
  for (var i = 0; i <= _gregorianCycleMonths; i++) {
    final first = DateTime.utc(year, month, 1);
    if (end != null && DateTime(year, month, 1).isAfter(end)) return null;
    final len = DateTime.utc(year, month + 1, 0).day;
    for (final d in candidates(year, month, len, first.weekday)) {
      final date = DateTime(year, month, d);
      if (date.isBefore(start)) continue;
      if (end != null && date.isAfter(end)) return null;
      return date;
    }
    if (++month > 12) {
      month = 1;
      year++;
    }
  }
  return null;
}

/// The visible blocks in [data] that clash with [candidate] (a new or
/// edited block, any project). Ignored: [candidate] itself (same id) and
/// deleted blocks / projects (not in [data]).
///
/// Sorted by first clash date, then project name, then block id.
List<TimeBlockClash> findTimeBlockClashes(
  TimeBlock candidate,
  ProjectsData data,
) {
  if (candidate.isDeleted) return const [];
  final out = <TimeBlockClash>[];
  for (final other in data.timeBlocks) {
    if (other.id == candidate.id) continue;
    final first = firstOverlapDate(candidate, other);
    if (first == null) continue;
    out.add(TimeBlockClash(
      block: other,
      project: data.project(other.projectId),
      firstDate: first,
    ));
  }
  out.sort((x, y) {
    var c = x.firstDate.compareTo(y.firstDate);
    if (c != 0) return c;
    c = (x.project?.name ?? '').compareTo(y.project?.name ?? '');
    return c != 0 ? c : x.block.id.compareTo(y.block.id);
  });
  return out;
}

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Short English label: `Mon–Fri`, `Mon, Wed, Fri`, `Every day`,
/// `1st, 15th of the month`.
String describeRecurrence(BlockRecurrence r) {
  switch (r) {
    case WeeklyRecurrence(:final weekdays):
      final days = weekdays.toList()..sort();
      if (days.length == 7) return 'Every day';
      final contiguous =
          days.length >= 3 && days.last - days.first == days.length - 1;
      if (contiguous) {
        return '${_weekdayShort[days.first - 1]}–${_weekdayShort[days.last - 1]}';
      }
      return days.map((d) => _weekdayShort[d - 1]).join(', ');
    case MonthlyRecurrence(:final monthDays):
      final days = monthDays.toList()..sort();
      return '${days.map(ordinal).join(', ')} of the month';
  }
}

/// `1st`, `2nd`, `3rd`, `4th`, `11th`, `21st`, …
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
