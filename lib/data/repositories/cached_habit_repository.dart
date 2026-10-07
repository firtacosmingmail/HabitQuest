import 'dart:async';

import '../../core/utils/stamps.dart';
import '../models/check_in.dart';
import '../models/completion_log.dart';
import '../models/habit.dart';
import '../sync/change_recorder.dart';
import 'habit_repository.dart';
import 'watch.dart';

/// Shared [HabitRepository] logic over an in-memory cache of every habit
/// and check-in record. Subclasses persist changes ([writeHabits] /
/// [writeCheckIns]); reads are always served from the cache. Members named
/// `habitRecords` / `checkInRecords` / `write*` are for subclasses only.
abstract class CachedHabitRepository implements HabitRepository {
  CachedHabitRepository({this.recorder, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Notified of local writes (the sync queue); `null` = no sync.
  final ChangeRecorder? recorder;
  final DateTime Function() _now;

  final Map<String, Habit> habitRecords = {};
  final Map<String, CheckIn> checkInRecords = {};

  final _habitChanges = StreamController<void>.broadcast(sync: true);
  final _completionChanges = StreamController<void>.broadcast(sync: true);
  List<Habit>? _habitsCache;
  CompletionLog? _logCache;

  /// Persists habit records (`null` value = remove the key).
  Future<void> writeHabits(Map<String, Habit?> changes);

  /// Persists check-in records (`null` value = remove the key).
  Future<void> writeCheckIns(Map<String, CheckIn?> changes);

  Future<void> clearStorage();

  Future<void> closeStorage();

  // Reads ---------------------------------------------------------------------

  @override
  List<Habit> getHabits() => _habitsCache ??= List.unmodifiable(
        sortHabits(habitRecords.values.where((h) => !h.isDeleted)),
      );

  @override
  Habit? getHabit(String id) {
    final h = habitRecords[id];
    return (h == null || h.isDeleted) ? null : h;
  }

  @override
  Habit? getHabitRecord(String id) => habitRecords[id];

  @override
  List<Habit> getAllHabitRecords() => sortHabits(habitRecords.values);

  @override
  Stream<List<Habit>> watchHabits() =>
      watchValue(getHabits, _habitChanges.stream);

  @override
  CompletionLog getCompletions() => _logCache ??= _buildLog();

  CompletionLog _buildLog() {
    final map = <String, Set<String>>{};
    for (final e in checkInRecords.entries) {
      final c = e.value;
      if (!c.isDone) continue;
      if (habitRecords[c.habitId]?.isDeleted ?? false) continue;
      final i = e.key.lastIndexOf('|');
      map.putIfAbsent(c.habitId, () => {}).add(e.key.substring(i + 1));
    }
    return CompletionLog.fromKeys(map);
  }

  @override
  Stream<CompletionLog> watchCompletions() =>
      watchValue(getCompletions, _completionChanges.stream);

  @override
  CheckIn? getCheckIn(String habitId, DateTime date) =>
      checkInRecords[CheckIn.keyFor(habitId, date)];

  @override
  List<CheckIn> getAllCheckIns() => checkInRecords.values.toList();

  // Local writes (recorded for sync) -------------------------------------------

  @override
  Future<void> saveHabit(Habit habit) async {
    await recorder?.recordChange(SyncEntityType.habit, habit.id);
    final previous = habitRecords[habit.id];
    habitRecords[habit.id] = habit;
    await writeHabits({habit.id: habit});
    _habitsChanged(
      alsoCompletions: (previous?.isDeleted ?? false) != habit.isDeleted,
    );
  }

  @override
  Future<void> deleteHabit(String id, {DateTime? at}) async {
    final current = habitRecords[id];
    if (current == null || current.isDeleted) return;
    final t = nextStamp(at ?? _now(), current.updatedAt);
    final tombstone = current.copyWith(updatedAt: t, deletedAt: () => t);
    await recorder?.recordChange(SyncEntityType.habit, id);
    habitRecords[id] = tombstone;
    await writeHabits({id: tombstone});
    _habitsChanged(alsoCompletions: true);
  }

  @override
  Future<void> setCompletion(
    String habitId,
    DateTime date,
    bool completed, {
    DateTime? updatedAt,
  }) async {
    final key = CheckIn.keyFor(habitId, date);
    final current = checkInRecords[key];
    if ((current?.isDone ?? false) == completed) return;
    final record = CheckIn(
      habitId: habitId,
      date: date,
      completed: completed,
      updatedAt: nextStamp(updatedAt ?? _now(), current?.updatedAt),
    );
    await recorder?.recordChange(SyncEntityType.checkIn, key);
    checkInRecords[key] = record;
    await writeCheckIns({key: record});
    _completionsChanged();
  }

  @override
  Future<List<DateTime>> deleteCompletionsFor(String habitId) async {
    final removed = checkInRecords.values
        .where((c) => c.habitId == habitId)
        .toList();
    if (removed.isEmpty) return [];
    for (final c in removed) {
      checkInRecords.remove(c.key);
    }
    await writeCheckIns({for (final c in removed) c.key: null});
    _completionsChanged();
    return (removed.where((c) => c.isDone).map((c) => c.date).toList()
      ..sort());
  }

  // Remote / maintenance ---------------------------------------------------------

  @override
  Future<void> applyRemote({
    List<Habit> habits = const [],
    List<CheckIn> checkIns = const [],
  }) async {
    if (habits.isNotEmpty) {
      for (final h in habits) {
        habitRecords[h.id] = h;
      }
      await writeHabits({for (final h in habits) h.id: h});
    }
    if (checkIns.isNotEmpty) {
      for (final c in checkIns) {
        checkInRecords[c.key] = c;
      }
      await writeCheckIns({for (final c in checkIns) c.key: c});
    }
    if (habits.isNotEmpty) {
      _habitsChanged(alsoCompletions: true);
    } else if (checkIns.isNotEmpty) {
      _completionsChanged();
    }
  }

  @override
  Future<void> clearAll() async {
    habitRecords.clear();
    checkInRecords.clear();
    await clearStorage();
    _habitsChanged(alsoCompletions: true);
  }

  @override
  Future<void> close() async {
    await _habitChanges.close();
    await _completionChanges.close();
    await closeStorage();
  }

  void _habitsChanged({bool alsoCompletions = false}) {
    _habitsCache = null;
    _logCache = null;
    if (!_habitChanges.isClosed) _habitChanges.add(null);
    // Deleting / restoring a habit hides / shows its check-ins.
    if (alsoCompletions && !_completionChanges.isClosed) {
      _completionChanges.add(null);
    }
  }

  void _completionsChanged() {
    _logCache = null;
    if (!_completionChanges.isClosed) _completionChanges.add(null);
  }
}
