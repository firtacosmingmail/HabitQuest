import '../models/completion_log.dart';
import '../models/habit.dart';

/// Persistence boundary for habits and check-ins.
///
/// Implementations: `HiveHabitRepository` (app) and `InMemoryHabitRepository`
/// (tests / previews). UI code should normally go through `HabitService` and
/// the Riverpod providers instead of using a repository directly.
abstract interface class HabitRepository {
  /// All habits (including archived), sorted by `createdAt`.
  List<Habit> getHabits();

  Habit? getHabit(String id);

  /// Emits the current habit list immediately, then after every change.
  Stream<List<Habit>> watchHabits();

  /// Inserts or replaces a habit (keyed by `id`).
  Future<void> saveHabit(Habit habit);

  /// Removes a habit. Does not touch completions; see [deleteCompletionsFor].
  Future<void> deleteHabit(String id);

  /// Snapshot of all check-ins.
  CompletionLog getCompletions();

  /// Emits the current log immediately, then after every change.
  Stream<CompletionLog> watchCompletions();

  /// Marks [habitId] as done / not done on [date]'s calendar day.
  Future<void> setCompletion(String habitId, DateTime date, bool completed);

  /// Removes every check-in of [habitId]; returns the removed dates.
  Future<List<DateTime>> deleteCompletionsFor(String habitId);

  /// Releases resources (closes boxes / controllers).
  Future<void> close();
}
