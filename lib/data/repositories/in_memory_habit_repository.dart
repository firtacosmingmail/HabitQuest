import 'dart:async';

import '../../core/utils/dates.dart';
import '../models/completion_log.dart';
import '../models/habit.dart';
import 'habit_repository.dart';
import 'watch.dart';

/// Non-persistent [HabitRepository] for tests, previews and widget tests.
class InMemoryHabitRepository implements HabitRepository {
  final Map<String, Habit> _habits = {};
  final Map<String, Set<String>> _completions = {};
  final _habitChanges = StreamController<void>.broadcast(sync: true);
  final _completionChanges = StreamController<void>.broadcast(sync: true);

  InMemoryHabitRepository({
    Iterable<Habit> habits = const [],
    Map<String, Iterable<DateTime>> completions = const {},
  }) {
    for (final h in habits) {
      _habits[h.id] = h;
    }
    for (final e in completions.entries) {
      _completions[e.key] = e.value.map(dateKey).toSet();
    }
  }

  @override
  List<Habit> getHabits() => sortHabits(_habits.values);

  @override
  Habit? getHabit(String id) => _habits[id];

  @override
  Stream<List<Habit>> watchHabits() =>
      watchValue(getHabits, _habitChanges.stream);

  @override
  Future<void> saveHabit(Habit habit) async {
    _habits[habit.id] = habit;
    _habitChanges.add(null);
  }

  @override
  Future<void> deleteHabit(String id) async {
    if (_habits.remove(id) != null) _habitChanges.add(null);
  }

  @override
  CompletionLog getCompletions() => CompletionLog.fromKeys(_completions);

  @override
  Stream<CompletionLog> watchCompletions() =>
      watchValue(getCompletions, _completionChanges.stream);

  @override
  Future<void> setCompletion(
    String habitId,
    DateTime date,
    bool completed,
  ) async {
    final set = _completions.putIfAbsent(habitId, () => {});
    final changed =
        completed ? set.add(dateKey(date)) : set.remove(dateKey(date));
    if (changed) _completionChanges.add(null);
  }

  @override
  Future<List<DateTime>> deleteCompletionsFor(String habitId) async {
    final removed = _completions.remove(habitId) ?? {};
    if (removed.isNotEmpty) _completionChanges.add(null);
    return (removed.toList()..sort()).map(parseDateKey).toList();
  }

  @override
  Future<void> close() async {
    await _habitChanges.close();
    await _completionChanges.close();
  }
}
