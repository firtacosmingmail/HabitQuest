import '../../../core/utils/dates.dart';
import 'clock_time.dart';
import 'json.dart';

/// On which days a time block recurs. Use an exhaustive `switch`.
///
/// * [WeeklyRecurrence] – ISO weekdays (1 = Monday … 7 = Sunday).
/// * [MonthlyRecurrence] – days of the month (1 … 31). A month without the
///   day (e.g. the 31st in April, the 30th in February) has NO session for
///   it that month (no shifting to the last day).
sealed class BlockRecurrence {
  const BlockRecurrence();

  /// Whether a session falls on [date]'s calendar day.
  bool occursOn(DateTime date);

  /// `{"type": "weekly", "weekdays": [...]}` or
  /// `{"type": "monthly", "monthDays": [...]}` (sorted ascending).
  Map<String, dynamic> toJson();

  /// Inverse of [toJson]. Throws [FormatException] on unknown types.
  static BlockRecurrence fromJson(Map<String, dynamic> json) {
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

final class WeeklyRecurrence extends BlockRecurrence {
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

final class MonthlyRecurrence extends BlockRecurrence {
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

/// A TIME BLOCK of a project: a recurring block of work, e.g. Mon–Fri
/// 10:00–13:00, optionally labelled ("Editing"). Its occurrences are
/// `Session`s (see `expandSessions`).
///
/// Times are local wall-clock times; [endTime] must be after [startTime]
/// (no blocks across midnight). Active from [effectiveStartDate] up to and
/// including [endDate], or open-ended when [endDate] is `null`.
class TimeBlock {
  /// UUID v4.
  final String id;

  /// The owning `Project.id`.
  final String projectId;

  /// Optional short label (trimmed, non-empty) shown with the project name.
  final String? label;
  final ClockTime startTime;
  final ClockTime endTime;
  final BlockRecurrence recurrence;

  /// Optional first day (date-only, local). `null` = the creation day.
  final DateTime? startDate;

  /// Optional last day (date-only, local, inclusive). `null` = open-ended.
  final DateTime? endDate;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  /// Throws [ArgumentError] unless [endTime] is after [startTime], or when
  /// [endDate] is before [startDate].
  TimeBlock({
    required this.id,
    required this.projectId,
    String? label,
    required this.startTime,
    required this.endTime,
    required this.recurrence,
    DateTime? startDate,
    DateTime? endDate,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : label = normalizeLabel(label),
        startDate = startDate == null ? null : dateOnly(startDate),
        endDate = endDate == null ? null : dateOnly(endDate),
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
    final s = this.startDate, e = this.endDate;
    if (s != null && e != null && e.isBefore(s)) {
      throw ArgumentError.value(
          dateKey(e), 'endDate', 'must not be before the start date');
    }
  }

  /// Trims [label]; blank → `null`.
  static String? normalizeLabel(String? label) {
    final t = label?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  bool get isDeleted => deletedAt != null;

  /// Whether the block has no end date.
  bool get isOpenEnded => endDate == null;

  /// The first day sessions can occur: [startDate], else the local
  /// calendar day of [createdAt].
  DateTime get effectiveStartDate => startDate ?? dateOnly(createdAt.toLocal());

  /// Session length in minutes.
  int get durationMinutes => endTime.minutesOfDay - startTime.minutesOfDay;

  TimeBlock copyWith({
    String? Function()? label,
    ClockTime? startTime,
    ClockTime? endTime,
    BlockRecurrence? recurrence,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      TimeBlock(
        id: id,
        projectId: projectId,
        label: label != null ? label() : this.label,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        recurrence: recurrence ?? this.recurrence,
        startDate: startDate != null ? startDate() : this.startDate,
        endDate: endDate != null ? endDate() : this.endDate,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'label': label,
        'startTime': startTime.toJson(),
        'endTime': endTime.toJson(),
        'recurrence': recurrence.toJson(),
        'startDate': startDate == null ? null : dateKey(startDate!),
        'endDate': endDate == null ? null : dateKey(endDate!),
        'createdAt': formatTimestamp(createdAt),
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory TimeBlock.fromJson(Map<String, dynamic> json) => TimeBlock(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        label: json['label'] as String?,
        startTime: ClockTime.parse(json['startTime'] as String),
        endTime: ClockTime.parse(json['endTime'] as String),
        recurrence: BlockRecurrence.fromJson(
          Map<String, dynamic>.from(json['recurrence'] as Map),
        ),
        startDate: json['startDate'] == null
            ? null
            : parseDateKey(json['startDate'] as String),
        endDate: json['endDate'] == null
            ? null
            : parseDateKey(json['endDate'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is TimeBlock &&
      other.id == id &&
      other.projectId == projectId &&
      other.label == label &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.recurrence == recurrence &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, projectId, label, startTime, endTime,
      recurrence, startDate, endDate, createdAt, deletedAt);

  @override
  String toString() =>
      'TimeBlock($id${label == null ? '' : ' "$label"'}, $recurrence $startTime–$endTime)';
}
