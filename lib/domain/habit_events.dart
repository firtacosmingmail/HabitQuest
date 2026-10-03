import '../data/models/habit.dart';

/// Emitted by `HabitService` after a check-in was persisted or removed.
class CompletionEvent {
  final String habitId;

  /// Date-only (local midnight) of the check-in.
  final DateTime date;

  /// `true` = checked in, `false` = check-in removed.
  final bool completed;

  const CompletionEvent({
    required this.habitId,
    required this.date,
    required this.completed,
  });

  @override
  bool operator ==(Object other) =>
      other is CompletionEvent &&
      other.habitId == habitId &&
      other.date == date &&
      other.completed == completed;

  @override
  int get hashCode => Object.hash(habitId, date, completed);

  @override
  String toString() => 'CompletionEvent($habitId, $date, $completed)';
}

enum HabitChangeType { created, updated, archived, unarchived, deleted }

/// Emitted by `HabitService` after a habit was persisted or removed.
class HabitChangeEvent {
  final HabitChangeType type;

  /// The habit after the change (for [HabitChangeType.deleted]: the habit as
  /// it was just before deletion).
  final Habit habit;

  /// For the previous state on `updated` / `archived` / `unarchived`.
  final Habit? previous;

  /// For [HabitChangeType.deleted]: the check-in dates that were removed
  /// with the habit (no `CompletionEvent`s are emitted for them).
  final List<DateTime> removedCompletions;

  const HabitChangeEvent({
    required this.type,
    required this.habit,
    this.previous,
    this.removedCompletions = const [],
  });

  @override
  String toString() => 'HabitChangeEvent(${type.name}, ${habit.id})';
}
