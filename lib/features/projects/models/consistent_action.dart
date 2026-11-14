import '../../../core/utils/dates.dart';
import 'clock_time.dart';
import 'json.dart';

/// On which days a consistent action recurs. Use an exhaustive `switch`.
///
/// * [WeeklyRecurrence] – ISO weekdays (1 = Monday … 7 = Sunday).
/// * [MonthlyRecurrence] – days of the month (1 … 31). A month without the
///   day (e.g. the 31st in April, the 30th in February) has NO session for
///   it that month (no shifting to the last day).
sealed class ActionRecurrence {
  const ActionRecurrence();

  /// Whether a session falls on [date]'s calendar day.
  bool occursOn(DateTime date);

  /// `{"type": "weekly", "weekdays": [...]}` or
  /// `{"type": "monthly", "monthDays": [...]}` (sorted ascending).
  Map<String, dynamic> toJson();

  /// Inverse of [toJson]. Throws [FormatException] on unknown types.
  static ActionRecurrence fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    List<int> ints(String key) =>
        (json[key] as List).map((e) => (e as num).toInt()).toList();
    switch (type) {
      case WeeklyRecurrence.typeName:
        return WeeklyRecurrence(ints('weekdays').toSet());
      case MonthlyRecurrence.typeName:
        return MonthlyRecurrence(ints('monthDays').toSet());
      default:
        throw FormatException('Unknown recurrence type', type);
    }
  }
}

final class WeeklyRecurrence extends ActionRecurrence {
  static const typeName = 'weekly';

  /// ISO weekdays (`DateTime.monday` = 1 … `DateTime.sunday` = 7). Non-empty.
  final Set<int> weekdays;

  WeeklyRecurrence(Set<int> weekdays) : weekdays = Set.unmodifiable(weekdays) {
    if (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7)) {
      throw ArgumentError.value(weekdays, 'weekdays', 'must be 1..7, non-empty');
    }
  }

  @override
  bool occursOn(DateTime date) => weekdays.contains(date.weekday);

  @override
  Map<String, dynamic> toJson() =>
      {'type': typeName, 'weekdays': weekdays.toList()..sort()};

  @override
  bool operator ==(Object other) =>
      other is WeeklyRecurrence &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(typeName, Object.hashAllUnordered(weekdays));

  @override
  String toString() => 'WeeklyRecurrence(${weekdays.toList()..sort()})';
}

final class MonthlyRecurrence extends ActionRecurrence {
  static const typeName = 'monthly';

  /// Days of the month (1 … 31). Non-empty.
  final Set<int> monthDays;

  MonthlyRecurrence(Set<int> monthDays)
      : monthDays = Set.unmodifiable(monthDays) {
    if (monthDays.isEmpty || monthDays.any((d) => d < 1 || d > 31)) {
      throw ArgumentError.value(
          monthDays, 'monthDays', 'must be 1..31, non-empty');
    }
  }

  /// A date's `day` only exists in its own month, so e.g. the 31st simply
  /// never matches in a 30-day month.
  @override
  bool occursOn(DateTime date) => monthDays.contains(date.day);

  @override
  Map<String, dynamic> toJson() =>
      {'type': typeName, 'monthDays': monthDays.toList()..sort()};

  @override
  bool operator ==(Object other) =>
      other is MonthlyRecurrence &&
      other.monthDays.length == monthDays.length &&
      other.monthDays.containsAll(monthDays);

  @override
  int get hashCode =>
      Object.hash(typeName, Object.hashAllUnordered(monthDays));

  @override
  String toString() => 'MonthlyRecurrence(${monthDays.toList()..sort()})';
}

/// A CONSISTENT ACTION of a target: a recurring time block, e.g. Mon–Fri
/// 10:00–13:00. Its occurrences are `Session`s (see `expandSessions`).
///
/// Times are local wall-clock times; [endTime] must be after [startTime]
/// (no blocks across midnight). Active from [effectiveStartDate] up to and
/// including the target's deadline.
class ConsistentAction {
  /// UUID v4.
  final String id;

  /// The owning `Target.id`.
  final String targetId;
  final ClockTime startTime;
  final ClockTime endTime;
  final ActionRecurrence recurrence;

  /// Optional first day (date-only, local). `null` = the creation day.
  final DateTime? startDate;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  /// Throws [ArgumentError] unless [endTime] is after [startTime].
  ConsistentAction({
    required this.id,
    required this.targetId,
    required this.startTime,
    required this.endTime,
    required this.recurrence,
    DateTime? startDate,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : startDate = startDate == null ? null : dateOnly(startDate),
        createdAt = createdAt.toUtc(),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc() {
    if (!startTime.isBefore(endTime)) {
      throw ArgumentError.value(
        '$startTime–$endTime',
        'endTime',
        'must be after the start time (no sessions across midnight)',
      );
    }
  }

  bool get isDeleted => deletedAt != null;

  /// The first day sessions can occur: [startDate], else the local
  /// calendar day of [createdAt].
  DateTime get effectiveStartDate => startDate ?? dateOnly(createdAt.toLocal());

  /// Session length in minutes.
  int get durationMinutes => endTime.minutesOfDay - startTime.minutesOfDay;

  ConsistentAction copyWith({
    ClockTime? startTime,
    ClockTime? endTime,
    ActionRecurrence? recurrence,
    DateTime? Function()? startDate,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      ConsistentAction(
        id: id,
        targetId: targetId,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        recurrence: recurrence ?? this.recurrence,
        startDate: startDate != null ? startDate() : this.startDate,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetId': targetId,
        'startTime': startTime.toJson(),
        'endTime': endTime.toJson(),
        'recurrence': recurrence.toJson(),
        'startDate': startDate == null ? null : dateKey(startDate!),
        'createdAt': formatTimestamp(createdAt),
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory ConsistentAction.fromJson(Map<String, dynamic> json) =>
      ConsistentAction(
        id: json['id'] as String,
        targetId: json['targetId'] as String,
        startTime: ClockTime.parse(json['startTime'] as String),
        endTime: ClockTime.parse(json['endTime'] as String),
        recurrence: ActionRecurrence.fromJson(
          Map<String, dynamic>.from(json['recurrence'] as Map),
        ),
        startDate: json['startDate'] == null
            ? null
            : parseDateKey(json['startDate'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is ConsistentAction &&
      other.id == id &&
      other.targetId == targetId &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.recurrence == recurrence &&
      other.startDate == startDate &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, targetId, startTime, endTime,
      recurrence, startDate, createdAt, deletedAt);

  @override
  String toString() =>
      'ConsistentAction($id, $recurrence $startTime–$endTime)';
}
