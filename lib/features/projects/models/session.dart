import '../../../core/utils/dates.dart';
import 'clock_time.dart';

/// One occurrence of a project's time block on a calendar day. Computed
/// (see `expandSessions`), never stored; only the user's attended mark is
/// stored (`SessionMark`).
class Session {
  final String timeBlockId;
  final String projectId;

  /// The block's label (`null` when it has none).
  final String? label;

  /// Date-only (local).
  final DateTime date;
  final ClockTime startTime;
  final ClockTime endTime;

  /// Whether the user marked it attended (`false` when unknown).
  final bool attended;

  Session({
    required this.timeBlockId,
    required this.projectId,
    this.label,
    required DateTime date,
    required this.startTime,
    required this.endTime,
    this.attended = false,
  }) : date = dateOnly(date);

  /// Local start (wall clock on [date]).
  DateTime get start => startTime.on(date);

  /// Local end (wall clock on [date]).
  DateTime get end => endTime.on(date);

  /// Same key as `SessionMark.keyFor(timeBlockId, date)`.
  String get key => '$timeBlockId|${dateKey(date)}';

  Session withAttended(bool attended) => Session(
        timeBlockId: timeBlockId,
        projectId: projectId,
        label: label,
        date: date,
        startTime: startTime,
        endTime: endTime,
        attended: attended,
      );

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.timeBlockId == timeBlockId &&
      other.projectId == projectId &&
      other.label == label &&
      other.date == date &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.attended == attended;

  @override
  int get hashCode => Object.hash(
      timeBlockId, projectId, label, date, startTime, endTime, attended);

  @override
  String toString() =>
      'Session($timeBlockId, ${dateKey(date)} $startTime–$endTime'
      '${attended ? ', attended' : ''})';
}
