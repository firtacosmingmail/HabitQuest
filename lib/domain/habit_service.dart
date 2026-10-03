import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/utils/dates.dart';
import '../data/models/habit.dart';
import '../data/models/habit_schedule.dart';
import '../data/repositories/habit_repository.dart';
import 'habit_events.dart';

/// Application service for all habit mutations. Screens, the game engine
/// and notifications should use this (via `habitServiceProvider`) rather
/// than the repository, so that events are emitted consistently.
class HabitService {
  final HabitRepository _repository;
  final DateTime Function() _now;
  final String Function() _newId;

  final _completionEvents = StreamController<CompletionEvent>.broadcast();
  final _habitChanges = StreamController<HabitChangeEvent>.broadcast();

  HabitService(
    this._repository, {
    DateTime Function()? now,
    String Function()? idGenerator,
  })  : _now = now ?? DateTime.now,
        _newId = idGenerator ?? const Uuid().v4;

  HabitRepository get repository => _repository;

  /// Broadcast stream of check-in changes (after persistence).
  Stream<CompletionEvent> get completionEvents => _completionEvents.stream;

  /// Broadcast stream of habit lifecycle changes (after persistence).
  Stream<HabitChangeEvent> get habitChanges => _habitChanges.stream;

  /// Today's date according to the injected clock.
  DateTime get today => dateOnly(_now());

  /// Creates and persists a habit. [startDate] defaults to today.
  Future<Habit> createHabit({
    required String name,
    required String emoji,
    required int colorValue,
    HabitSchedule schedule = const DailySchedule(),
    ReminderTime? reminderTime,
    DateTime? startDate,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final habit = Habit(
      id: _newId(),
      name: trimmed,
      emoji: emoji,
      colorValue: colorValue,
      schedule: schedule,
      reminderTime: reminderTime,
      createdAt: _now(),
      startDate: startDate ?? today,
    );
    await _repository.saveHabit(habit);
    _habitChanges.add(
      HabitChangeEvent(type: HabitChangeType.created, habit: habit),
    );
    return habit;
  }

  /// Persists changes to an existing habit (matched by id).
  ///
  /// If the archived flag changed, an `archived`/`unarchived` event is
  /// emitted instead of `updated`.
  Future<Habit> updateHabit(Habit habit) async {
    final previous = _require(habit.id);
    if (habit.name.trim().isEmpty) {
      throw ArgumentError.value(habit.name, 'name', 'must not be empty');
    }
    await _repository.saveHabit(habit);
    final type = previous.archived == habit.archived
        ? HabitChangeType.updated
        : (habit.archived
            ? HabitChangeType.archived
            : HabitChangeType.unarchived);
    _habitChanges.add(
      HabitChangeEvent(type: type, habit: habit, previous: previous),
    );
    return habit;
  }

  /// Archives (or with `archived: false`, restores) a habit. Check-ins are
  /// kept. Archived habits are never due.
  Future<Habit> archiveHabit(String habitId, {bool archived = true}) async {
    final habit = _require(habitId);
    if (habit.archived == archived) return habit;
    return updateHabit(habit.copyWith(archived: archived));
  }

  /// Deletes a habit and all of its check-ins.
  Future<void> deleteHabit(String habitId) async {
    final habit = _require(habitId);
    final removed = await _repository.deleteCompletionsFor(habitId);
    await _repository.deleteHabit(habitId);
    _habitChanges.add(HabitChangeEvent(
      type: HabitChangeType.deleted,
      habit: habit,
      removedCompletions: removed,
    ));
  }

  /// Whether [habitId] is checked in on [date]'s calendar day.
  bool isCompleted(String habitId, DateTime date) =>
      _repository.getCompletions().isCompleted(habitId, date);

  /// Flips the check-in of [habitId] on [date] and returns the new state
  /// (`true` = now completed). Future dates are rejected.
  Future<bool> toggleCompletion(String habitId, DateTime date) async {
    final completed = !isCompleted(habitId, date);
    await setCompletion(habitId, date, completed);
    return completed;
  }

  /// Sets the check-in of [habitId] on [date]. No-op (and no event) if the
  /// state does not change. Throws [ArgumentError] for dates after today and
  /// [StateError] for unknown habits.
  Future<void> setCompletion(
    String habitId,
    DateTime date,
    bool completed,
  ) async {
    _require(habitId);
    final d = dateOnly(date);
    if (d.isAfter(today)) {
      throw ArgumentError.value(date, 'date', 'cannot check in in the future');
    }
    if (isCompleted(habitId, d) == completed) return;
    await _repository.setCompletion(habitId, d, completed);
    _completionEvents.add(
      CompletionEvent(habitId: habitId, date: d, completed: completed),
    );
  }

  Habit _require(String habitId) {
    final habit = _repository.getHabit(habitId);
    if (habit == null) throw StateError('Unknown habit: $habitId');
    return habit;
  }

  /// Closes the event streams.
  Future<void> dispose() async {
    await _completionEvents.close();
    await _habitChanges.close();
  }
}
