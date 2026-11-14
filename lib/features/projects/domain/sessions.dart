/// Pure session expansion: consistent actions → dated sessions.
///
/// Rules (see docs/PROJECTS.md "Recurrence"):
/// * A session exists on each calendar day `d` with
///   `effectiveStartDate <= d <= target.deadline` and
///   `recurrence.occursOn(d)`.
/// * Monthly days missing from a month (e.g. the 31st in April) have no
///   session that month.
/// * Times are local wall-clock times; the date iteration uses
///   `addDays` (calendar days), so DST never moves or drops a session.
library;

import '../../../core/utils/dates.dart';
import '../models/consistent_action.dart';
import '../models/projects_data.dart';
import '../models/session.dart';
import '../models/target.dart';

/// The calendar days (date-only, ascending) on which [action] has a
/// session, within `[from, to]` (inclusive, normalised to dates) and the
/// action's active window `[effectiveStartDate, deadline]`.
List<DateTime> sessionDates(
  ConsistentAction action, {
  required DateTime deadline,
  required DateTime from,
  required DateTime to,
}) {
  var day = _max(dateOnly(from), action.effectiveStartDate);
  final last = _min(dateOnly(to), dateOnly(deadline));
  final out = <DateTime>[];
  while (!day.isAfter(last)) {
    if (action.recurrence.occursOn(day)) out.add(day);
    day = addDays(day, 1);
  }
  return out;
}

/// Whether [action] has a session on [date] (inside its active window).
bool hasSessionOn(
  ConsistentAction action, {
  required DateTime deadline,
  required DateTime date,
}) {
  final d = dateOnly(date);
  return !d.isBefore(action.effectiveStartDate) &&
      !d.isAfter(dateOnly(deadline)) &&
      action.recurrence.occursOn(d);
}

/// The sessions of [action] (of [target]) within `[from, to]`, ascending.
/// [attended] fills `Session.attended` (default: none attended).
List<Session> expandSessions(
  ConsistentAction action,
  Target target, {
  required DateTime from,
  required DateTime to,
  bool Function(String actionId, DateTime date)? attended,
}) {
  assert(action.targetId == target.id, 'action belongs to another target');
  return [
    for (final d in sessionDates(action,
        deadline: target.deadline, from: from, to: to))
      Session(
        actionId: action.id,
        targetId: target.id,
        projectId: target.projectId,
        date: d,
        startTime: action.startTime,
        endTime: action.endTime,
        attended: attended?.call(action.id, d) ?? false,
      ),
  ];
}

/// Every session of every visible action in [data] within `[from, to]`,
/// with the attended marks, sorted by date, then start time, then action
/// id. Sessions of targets marked done and of archived projects are
/// included unless excluded with the flags.
List<Session> sessionsInRange(
  ProjectsData data, {
  required DateTime from,
  required DateTime to,
  bool includeDoneTargets = true,
  bool includeArchivedProjects = true,
}) {
  final out = <Session>[];
  for (final a in data.actions) {
    final t = data.target(a.targetId);
    if (t == null) continue;
    if (!includeDoneTargets && t.isDone) continue;
    if (!includeArchivedProjects && (data.project(t.projectId)?.archived ?? false)) {
      continue;
    }
    out.addAll(
      expandSessions(a, t, from: from, to: to, attended: data.isAttended),
    );
  }
  out.sort(compareSessions);
  return out;
}

/// Date, then start time, then end time, then action id.
int compareSessions(Session a, Session b) {
  var c = a.date.compareTo(b.date);
  if (c != 0) return c;
  c = a.startTime.compareTo(b.startTime);
  if (c != 0) return c;
  c = a.endTime.compareTo(b.endTime);
  if (c != 0) return c;
  return a.actionId.compareTo(b.actionId);
}

DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
