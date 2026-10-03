import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../core/utils/dates.dart';
import '../models/completion_log.dart';
import '../models/habit.dart';
import 'habit_repository.dart';
import 'watch.dart';

/// [HabitRepository] backed by two hive_ce boxes (works on iOS, Android, web).
///
/// * `habits` box: `habitId -> JSON string` of `Habit.toJson()`.
/// * `completions` box: `"<habitId>|yyyy-MM-dd" -> true`.
///
/// No type adapters / code generation are needed. Call `Hive.initFlutter()`
/// (app) or `Hive.init(path)` (tests) before [HiveHabitRepository.open].
class HiveHabitRepository implements HabitRepository {
  static const habitsBoxName = 'habits';
  static const completionsBoxName = 'completions';
  static const _sep = '|';

  final Box<String> _habitsBox;
  final Box<bool> _completionsBox;

  HiveHabitRepository._(this._habitsBox, this._completionsBox);

  /// Opens (or creates) the boxes. [boxPrefix] lets tests isolate data.
  static Future<HiveHabitRepository> open({String boxPrefix = ''}) async {
    final habits = await Hive.openBox<String>('$boxPrefix$habitsBoxName');
    final completions =
        await Hive.openBox<bool>('$boxPrefix$completionsBoxName');
    return HiveHabitRepository._(habits, completions);
  }

  static String _completionKey(String habitId, DateTime date) =>
      '$habitId$_sep${dateKey(date)}';

  @override
  List<Habit> getHabits() => sortHabits(
        _habitsBox.values.map(
          (s) => Habit.fromJson(jsonDecode(s) as Map<String, dynamic>),
        ),
      );

  @override
  Habit? getHabit(String id) {
    final s = _habitsBox.get(id);
    return s == null
        ? null
        : Habit.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  @override
  Stream<List<Habit>> watchHabits() =>
      watchValue(getHabits, _habitsBox.watch());

  @override
  Future<void> saveHabit(Habit habit) =>
      _habitsBox.put(habit.id, jsonEncode(habit.toJson()));

  @override
  Future<void> deleteHabit(String id) => _habitsBox.delete(id);

  @override
  CompletionLog getCompletions() {
    final map = <String, Set<String>>{};
    for (final key in _completionsBox.keys.cast<String>()) {
      final i = key.lastIndexOf(_sep);
      if (i <= 0) continue;
      map.putIfAbsent(key.substring(0, i), () => {}).add(key.substring(i + 1));
    }
    return CompletionLog.fromKeys(map);
  }

  @override
  Stream<CompletionLog> watchCompletions() =>
      watchValue(getCompletions, _completionsBox.watch());

  @override
  Future<void> setCompletion(String habitId, DateTime date, bool completed) {
    final key = _completionKey(habitId, date);
    return completed ? _completionsBox.put(key, true) : _completionsBox.delete(key);
  }

  @override
  Future<List<DateTime>> deleteCompletionsFor(String habitId) async {
    final prefix = '$habitId$_sep';
    final keys = _completionsBox.keys
        .cast<String>()
        .where((k) => k.startsWith(prefix))
        .toList()
      ..sort();
    await _completionsBox.deleteAll(keys);
    return keys.map((k) => parseDateKey(k.substring(prefix.length))).toList();
  }

  @override
  Future<void> close() async {
    await _habitsBox.close();
    await _completionsBox.close();
  }
}
