import 'dart:convert';
import 'dart:developer' as developer;

import 'package:hive_ce/hive.dart';

import '../models/check_in.dart';
import '../models/habit.dart';
import '../sync/change_recorder.dart';
import 'cached_habit_repository.dart';

/// [HabitRepository] backed by two hive_ce boxes (works on iOS, Android, web).
///
/// * `habits` box: `habitId -> JSON string` of `Habit.toJson()` (tombstones
///   included).
/// * `completions` box: `"<habitId>|yyyy-MM-dd" -> JSON string` of
///   `CheckIn.toJson()`.
///
/// Data written by the pre-sync version is still readable: habits without
/// `updatedAt` default to their `createdAt`, and legacy check-ins (stored as
/// `true`) are migrated on [open] to records stamped with the migration
/// time.
///
/// No type adapters / code generation are needed. Call `Hive.initFlutter()`
/// (app) or `Hive.init(path)` (tests) before [HiveHabitRepository.open].
class HiveHabitRepository extends CachedHabitRepository {
  static const habitsBoxName = 'habits';
  static const completionsBoxName = 'completions';

  final Box<String> _habitsBox;
  final Box<dynamic> _completionsBox;

  HiveHabitRepository._(
    this._habitsBox,
    this._completionsBox, {
    super.recorder,
    super.now,
  });

  /// Opens (or creates) the boxes and loads them into memory. [boxPrefix]
  /// lets tests isolate data. Local writes are reported to [recorder].
  static Future<HiveHabitRepository> open({
    String boxPrefix = '',
    ChangeRecorder? recorder,
    DateTime Function()? now,
  }) async {
    final habits = await Hive.openBox<String>('$boxPrefix$habitsBoxName');
    final completions = await Hive.openBox<dynamic>(
      '$boxPrefix$completionsBoxName',
    );
    final repo = HiveHabitRepository._(
      habits,
      completions,
      recorder: recorder,
      now: now,
    );
    await repo._load((now ?? DateTime.now)());
    return repo;
  }

  Future<void> _load(DateTime now) async {
    for (final key in _habitsBox.keys.cast<String>()) {
      try {
        final h = Habit.fromJson(
          jsonDecode(_habitsBox.get(key)!) as Map<String, dynamic>,
        );
        habitRecords[h.id] = h;
      } on Object catch (e) {
        developer.log('Skipping unreadable habit $key: $e', name: 'Hive');
      }
    }
    final migrated = <String, String>{};
    for (final key in _completionsBox.keys.cast<String>()) {
      final value = _completionsBox.get(key);
      CheckIn? record;
      if (value is bool) {
        // Pre-sync format: "<habitId>|<date>" -> true.
        final parsed = CheckIn.parseKey(key);
        if (parsed != null && value) {
          record = CheckIn(
            habitId: parsed.$1,
            date: parsed.$2,
            completed: true,
            updatedAt: now,
          );
          migrated[key] = jsonEncode(record.toJson());
        }
      } else if (value is String) {
        try {
          record = CheckIn.fromJson(jsonDecode(value) as Map<String, dynamic>);
        } on Object catch (e) {
          developer.log('Skipping unreadable check-in $key: $e', name: 'Hive');
        }
      }
      if (record != null) checkInRecords[record.key] = record;
    }
    if (migrated.isNotEmpty) await _completionsBox.putAll(migrated);
  }

  @override
  Future<void> writeHabits(Map<String, Habit?> changes) async {
    final puts = <String, String>{};
    final deletes = <String>[];
    changes.forEach((id, h) {
      if (h == null) {
        deletes.add(id);
      } else {
        puts[id] = jsonEncode(h.toJson());
      }
    });
    if (puts.isNotEmpty) await _habitsBox.putAll(puts);
    if (deletes.isNotEmpty) await _habitsBox.deleteAll(deletes);
  }

  @override
  Future<void> writeCheckIns(Map<String, CheckIn?> changes) async {
    final puts = <String, String>{};
    final deletes = <String>[];
    changes.forEach((key, c) {
      if (c == null) {
        deletes.add(key);
      } else {
        puts[key] = jsonEncode(c.toJson());
      }
    });
    if (puts.isNotEmpty) await _completionsBox.putAll(puts);
    if (deletes.isNotEmpty) await _completionsBox.deleteAll(deletes);
  }

  @override
  Future<void> clearStorage() async {
    await _habitsBox.clear();
    await _completionsBox.clear();
  }

  @override
  Future<void> closeStorage() async {
    await _habitsBox.close();
    await _completionsBox.close();
  }
}
