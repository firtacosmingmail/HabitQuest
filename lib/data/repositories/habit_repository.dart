import '../models/check_in.dart';
import '../models/completion_log.dart';
import '../models/habit.dart';

/// Persistence boundary for habits and check-ins.
///
/// Implementations: `HiveHabitRepository` (app) and `InMemoryHabitRepository`
/// (tests / previews). UI code should normally go through `HabitService` and
/// the Riverpod providers instead of using a repository directly.
///
/// Sync: every local write ([saveHabit], [deleteHabit], [setCompletion])
/// stamps `updatedAt` and is reported to the optional `ChangeRecorder` (the
/// sync queue). [applyRemote] writes server data without recording it.
/// Deleted habits are kept as tombstones (`deletedAt`) but hidden from every
/// read except [getHabitRecord] / [getAllHabitRecords]; their check-ins are
/// hidden from [getCompletions] too.
abstract interface class HabitRepository {
  /// All live habits (including archived, excluding deleted), sorted by
  /// `createdAt`.
  List<Habit> getHabits();

  /// A live habit (`null` if unknown or deleted).
  Habit? getHabit(String id);

  /// A habit record including tombstones (sync).
  Habit? getHabitRecord(String id);

  /// Every habit record including tombstones (sync).
  List<Habit> getAllHabitRecords();

  /// Emits the current habit list immediately, then after every change.
  Stream<List<Habit>> watchHabits();

  /// Inserts or replaces a habit (keyed by `id`). The caller stamps
  /// `updatedAt` (see `HabitService`).
  Future<void> saveHabit(Habit habit);

  /// Deletes a habit: stores a tombstone with `deletedAt = updatedAt = at`
  /// (default now). Does not touch completions; see [deleteCompletionsFor].
  Future<void> deleteHabit(String id, {DateTime? at});

  /// Snapshot of all visible check-ins (done, not deleted, habit not
  /// deleted).
  CompletionLog getCompletions();

  /// Emits the current log immediately, then after every change.
  Stream<CompletionLog> watchCompletions();

  /// Marks [habitId] as done / not done on [date]'s calendar day, stamping
  /// [updatedAt] (default now).
  Future<void> setCompletion(
    String habitId,
    DateTime date,
    bool completed, {
    DateTime? updatedAt,
  });

  /// A stored check-in record (any state), by habit and date.
  CheckIn? getCheckIn(String habitId, DateTime date);

  /// Every stored check-in record (sync).
  List<CheckIn> getAllCheckIns();

  /// Removes every check-in record of [habitId] locally (not synced: the
  /// habit's tombstone hides them everywhere); returns the dates that were
  /// done.
  Future<List<DateTime>> deleteCompletionsFor(String habitId);

  /// Writes records that came from the server (already resolved by
  /// last-write-wins) without recording them for upload.
  Future<void> applyRemote({
    List<Habit> habits = const [],
    List<CheckIn> checkIns = const [],
  });

  /// Removes everything (account switch).
  Future<void> clearAll();

  /// Releases resources (closes boxes / controllers).
  Future<void> close();
}
