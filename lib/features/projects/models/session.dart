import '../../../core/utils/dates.dart';
import 'clock_time.dart';

/// One occurrence of a consistent action on a calendar day. Computed (see
/// `expandSessions`), never stored; only the user's attended mark is stored
/// (`SessionMark`).
class Session {
  final String actionId;
  final String targetId;
  final String projectId;

  /// Date-only (local).
  final DateTime date;
  final ClockTime startTime;
  final ClockTime endTime;

  /// Whether the user marked it attended (`false` when unknown).
  final bool attended;

  Session({
    required this.actionId,
    required this.targetId,
    required this.projectId,
    required DateTime date,
    required this.startTime,
    required this.endTime,
    this.attended = false,
  }) : date = dateOnly(date);

  /// Local start (wall clock on [date]).
  DateTime get start => startTime.on(date);

  /// Local end (wall clock on [date]).
  DateTime get end => endTime.on(date);

  /// Same key as `SessionMark.keyFor(actionId, date)`.
  String get key => '$actionId|${dateKey(date)}';

  Session withAttended(bool attended) => Session(
        actionId: actionId,
        targetId: targetId,
        projectId: projectId,
        date: date,
        startTime: startTime,
        endTime: endTime,
        attended: attended,
      );

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.actionId == actionId &&
      other.targetId == targetId &&
      other.projectId == projectId &&
      other.date == date &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.attended == attended;

  @override
  int get hashCode => Object.hash(
      actionId, targetId, projectId, date, startTime, endTime, attended);

  @override
  String toString() =>
      'Session($actionId, ${dateKey(date)} $startTime–$endTime'
      '${attended ? ', attended' : ''})';
}
