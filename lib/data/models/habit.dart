import '../../core/utils/dates.dart';
import 'habit_schedule.dart';

/// A reminder time of day (local), independent of Flutter's `TimeOfDay`
/// so the data layer stays pure Dart.
class ReminderTime {
  final int hour; // 0..23
  final int minute; // 0..59

  const ReminderTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory ReminderTime.fromJson(Map<String, dynamic> json) => ReminderTime(
        hour: (json['hour'] as num).toInt(),
        minute: (json['minute'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// A habit. Immutable; use [copyWith] to change it and `HabitService` to
/// persist the change.
class Habit {
  final String id;
  final String name;

  /// A single emoji (grapheme) used as the habit's icon.
  final String emoji;

  /// ARGB colour value (`Color.toARGB32()`); see `HabitPalette`.
  final int colorValue;
  final HabitSchedule schedule;
  final ReminderTime? reminderTime;
  final DateTime createdAt;

  /// Date-only (local midnight). The habit is never due before this date and
  /// `EveryNDaysSchedule` counts from it.
  final DateTime startDate;
  final bool archived;

  /// Last local or remote change (UTC). Drives last-write-wins sync.
  /// Defaults to [createdAt] (data written before sync existed).
  final DateTime updatedAt;

  /// Tombstone (UTC): the habit was deleted. Tombstoned habits are hidden
  /// by the repositories (UI, recurrence, streaks, notifications) and only
  /// kept so the deletion can sync.
  final DateTime? deletedAt;

  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.schedule,
    this.reminderTime,
    required this.createdAt,
    required DateTime startDate,
    this.archived = false,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : startDate = dateOnly(startDate),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc();

  bool get isDeleted => deletedAt != null;

  Habit copyWith({
    String? name,
    String? emoji,
    int? colorValue,
    HabitSchedule? schedule,
    ReminderTime? reminderTime,
    bool clearReminderTime = false,
    DateTime? startDate,
    bool? archived,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      colorValue: colorValue ?? this.colorValue,
      schedule: schedule ?? this.schedule,
      reminderTime:
          clearReminderTime ? null : (reminderTime ?? this.reminderTime),
      createdAt: createdAt,
      startDate: startDate ?? this.startDate,
      archived: archived ?? this.archived,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorValue': colorValue,
        'schedule': schedule.toJson(),
        'reminderTime': reminderTime?.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'startDate': dateKey(startDate),
        'archived': archived,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  /// Tolerant of data saved before sync existed (no `updatedAt` /
  /// `deletedAt`): `updatedAt` then defaults to `createdAt`.
  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        colorValue: (json['colorValue'] as num).toInt(),
        schedule: HabitSchedule.fromJson(
          Map<String, dynamic>.from(json['schedule'] as Map),
        ),
        reminderTime: json['reminderTime'] == null
            ? null
            : ReminderTime.fromJson(
                Map<String, dynamic>.from(json['reminderTime'] as Map),
              ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        startDate: parseDateKey(json['startDate'] as String),
        archived: json['archived'] as bool? ?? false,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String),
      );

  /// Content equality. [updatedAt] is sync metadata and deliberately not
  /// compared ([deletedAt] is).
  @override
  bool operator ==(Object other) =>
      other is Habit &&
      other.id == id &&
      other.name == name &&
      other.emoji == emoji &&
      other.colorValue == colorValue &&
      other.schedule == schedule &&
      other.reminderTime == reminderTime &&
      other.createdAt == createdAt &&
      other.startDate == startDate &&
      other.archived == archived &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, name, emoji, colorValue, schedule,
      reminderTime, createdAt, startDate, archived, deletedAt);

  @override
  String toString() => 'Habit($id, $emoji $name, $schedule'
      '${archived ? ', archived' : ''})';
}
