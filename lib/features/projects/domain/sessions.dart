/// Pure session expansion: time blocks → dated sessions.
///
/// Rules (see docs/PROJECTS.md "Recurrence"):
/// * A session exists on each calendar day `d` with
///   `effectiveStartDate <= d` and (`endDate == null` or `d <= endDate`)
///   and `recurrence.occursOn(d)`. Open-ended blocks (no end date) have
///   sessions forever; callers always pass a bounded `[from, to]` range.
/// * Monthly days missing from a month (e.g. the 31st in April) have no
///   session that month.
/// * Times are local wall-clock times; the date iteration uses
///   `addDays` (calendar days), so DST never moves or drops a session.
library;

import '../../../core/utils/dates.dart';
import '../models/projects_data.dart';
import '../models/session.dart';
import '../models/time_block.dart';

/// The calendar days (date-only, ascending) on which [block] has a
/// session, within `[from, to]` (inclusive, normalised to dates) and the
/// block's active window `[effectiveStartDate, endDate ?? ∞]`.
List<DateTime> sessionDates(
  TimeBlock block, {
  required DateTime from,
  required DateTime to,
}) {
  var day = _max(dateOnly(from), block.effectiveStartDate);
  final end = block.endDate;
  final last = end == null ? dateOnly(to) : _min(dateOnly(to), end);
  final out = <DateTime>[];
  while (!day.isAfter(last)) {
    if (block.recurrence.occursOn(day)) out.add(day);
    day = addDays(day, 1);
  }
  return out;
}

/// Whether [block] has a session on [date] (inside its active window).
bool hasSessionOn(TimeBlock block, {required DateTime date}) {
  final d = dateOnly(date);
  final end = block.endDate;
  return !d.isBefore(block.effectiveStartDate) &&
      (end == null || !d.isAfter(end)) &&
      block.recurrence.occursOn(d);
}

/// The sessions of [block] within `[from, to]`, ascending. [attended]
/// fills `Session.attended` (default: none attended).
List<Session> expandSessions(
  TimeBlock block, {
  required DateTime from,
  required DateTime to,
  bool Function(String timeBlockId, DateTime date)? attended,
}) =>
    [
      for (final d in sessionDates(block, from: from, to: to))
        Session(
          timeBlockId: block.id,
          projectId: block.projectId,
          label: block.label,
          date: d,
          startTime: block.startTime,
          endTime: block.endTime,
          attended: attended?.call(block.id, d) ?? false,
        ),
    ];

/// Every session of every visible time block in [data] within
/// `[from, to]`, with the attended marks, sorted by date, then start time,
/// then block id. Sessions of archived projects are included unless
/// excluded with [includeArchivedProjects].
List<Session> sessionsInRange(
  ProjectsData data, {
  required DateTime from,
  required DateTime to,
  bool includeArchivedProjects = true,
}) {
  final out = <Session>[];
  for (final b in data.timeBlocks) {
    if (!includeArchivedProjects &&
        (data.project(b.projectId)?.archived ?? false)) {
      continue;
    }
    out.addAll(
      expandSessions(b, from: from, to: to, attended: data.isAttended),
    );
  }
  out.sort(compareSessions);
  return out;
}

/// Date, then start time, then end time, then block id.
int compareSessions(Session a, Session b) {
  var c = a.date.compareTo(b.date);
  if (c != 0) return c;
  c = a.startTime.compareTo(b.startTime);
  if (c != 0) return c;
  c = a.endTime.compareTo(b.endTime);
  if (c != 0) return c;
  return a.timeBlockId.compareTo(b.timeBlockId);
}

DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
