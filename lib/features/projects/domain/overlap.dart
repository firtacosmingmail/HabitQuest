/// Pure overlap detection between consistent actions.
///
/// Rule (see docs/PROJECTS.md "Overlap"): two actions overlap when, on some
/// calendar day, both have a session and their wall-clock intervals
/// `[start, end)` intersect. Touching ends (10:00–13:00 and 13:00–15:00) do
/// NOT overlap. Deleted actions, actions of deleted targets / projects and
/// actions of targets marked done are ignored.
library;

import '../../../core/utils/dates.dart';
import '../models/clock_time.dart';
import '../models/consistent_action.dart';
import '../models/project.dart';
import '../models/projects_data.dart';
import '../models/target.dart';

/// Another action that clashes with a candidate action.
class ActionClash {
  /// The existing, clashing action.
  final ConsistentAction action;

  /// Its target (for the message: title, deadline).
  final Target target;

  /// Its project (`null` only if the snapshot lacks it).
  final Project? project;

  /// The first calendar day on which both have overlapping sessions.
  final DateTime firstDate;

  const ActionClash({
    required this.action,
    required this.target,
    required this.project,
    required this.firstDate,
  });

  /// e.g. `"5 videos" (Content business), Mon–Fri 10:00–13:00, first on 2026-11-16`.
  String describe() {
    final where = project == null
        ? '"${target.title}"'
        : '"${target.title}" (${project!.name})';
    return '$where, ${describeRecurrence(action.recurrence)} '
        '${action.startTime}–${action.endTime}, '
        'first on ${dateKey(firstDate)}';
  }

  @override
  String toString() => 'ActionClash(${action.id}, ${dateKey(firstDate)})';
}

/// Thrown by `ProjectService` when saving an action (or a target change
/// that extends / revives its actions) would overlap other actions.
class ActionOverlapException implements Exception {
  /// The action that was being saved.
  final ConsistentAction action;

  /// Every clashing action, sorted by [ActionClash.firstDate].
  final List<ActionClash> clashes;

  const ActionOverlapException(this.action, this.clashes);

  /// A user-facing English message naming the clashing targets and times.
  String get message {
    final head = 'This time block (${describeRecurrence(action.recurrence)} '
        '${action.startTime}–${action.endTime}) overlaps ';
    return head + clashes.map((c) => c.describe()).join('; ');
  }

  @override
  String toString() => 'ActionOverlapException: $message';
}

/// Whether two wall-clock intervals `[aStart, aEnd)` and `[bStart, bEnd)`
/// intersect (touching ends do not).
bool timesOverlap(ClockTime aStart, ClockTime aEnd, ClockTime bStart,
        ClockTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// The first calendar day on which [a] (deadline [aDeadline]) and [b]
/// (deadline [bDeadline]) have overlapping sessions, or `null`.
DateTime? firstOverlapDate(
  ConsistentAction a,
  DateTime aDeadline,
  ConsistentAction b,
  DateTime bDeadline,
) {
  if (!timesOverlap(a.startTime, a.endTime, b.startTime, b.endTime)) {
    return null;
  }
  final from = a.effectiveStartDate.isAfter(b.effectiveStartDate)
      ? a.effectiveStartDate
      : b.effectiveStartDate;
  final ad = dateOnly(aDeadline), bd = dateOnly(bDeadline);
  final to = ad.isBefore(bd) ? ad : bd;
  for (var d = from; !d.isAfter(to); d = addDays(d, 1)) {
    if (a.recurrence.occursOn(d) && b.recurrence.occursOn(d)) return d;
  }
  return null;
}

/// The actions in [data] that clash with [candidate], a new or edited
/// action of [candidateTarget] (pass the target as it will be saved, so an
/// edited deadline counts). Actions of [candidateTarget] itself are
/// evaluated with [candidateTarget]'s deadline.
///
/// Ignored: [candidate] itself (same id), deleted actions / targets /
/// projects (not in [data]) and actions of targets marked done. If
/// [candidateTarget] is marked done, there is no clash (its actions are
/// ignored by the rule too).
///
/// Sorted by first clash date, then target title, then action id.
List<ActionClash> findActionClashes(
  ConsistentAction candidate,
  Target candidateTarget,
  ProjectsData data,
) {
  if (candidate.isDeleted ||
      candidateTarget.isDeleted ||
      candidateTarget.isDone) {
    return const [];
  }
  final out = <ActionClash>[];
  for (final other in data.actions) {
    if (other.id == candidate.id) continue;
    final t = other.targetId == candidateTarget.id
        ? candidateTarget
        : data.target(other.targetId);
    if (t == null || t.isDone) continue;
    final first = firstOverlapDate(
      candidate,
      candidateTarget.deadline,
      other,
      t.deadline,
    );
    if (first == null) continue;
    out.add(ActionClash(
      action: other,
      target: t,
      project: data.project(t.projectId),
      firstDate: first,
    ));
  }
  out.sort((x, y) {
    var c = x.firstDate.compareTo(y.firstDate);
    if (c != 0) return c;
    c = x.target.title.compareTo(y.target.title);
    return c != 0 ? c : x.action.id.compareTo(y.action.id);
  });
  return out;
}

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Short English label: `Mon–Fri`, `Mon, Wed, Fri`, `Every day`,
/// `1st, 15th of the month`.
String describeRecurrence(ActionRecurrence r) {
  switch (r) {
    case WeeklyRecurrence(:final weekdays):
      final days = weekdays.toList()..sort();
      if (days.length == 7) return 'Every day';
      final contiguous = days.length >= 3 && days.last - days.first == days.length - 1;
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
