import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/habit_repository.dart';
import 'package:habit_quest/data/repositories/hive_habit_repository.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/fixtures.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('habit_quest_hive');
    Hive.init(tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  var n = 0;
  final factories = <String, Future<HabitRepository> Function()>{
    'InMemory': () async => InMemoryHabitRepository(),
    'Hive': () => HiveHabitRepository.open(boxPrefix: 't${n++}_'),
  };

  for (final entry in factories.entries) {
    group(entry.key, () {
      late HabitRepository repo;
      setUp(() async => repo = await entry.value());
      tearDown(() => repo.close());

      test('habit CRUD, sorted by createdAt', () async {
        final a = habit(id: 'a', startDate: d(2026, 1, 2));
        final b = habit(id: 'b', startDate: d(2026, 1, 1),
            schedule: TimesPerWeekSchedule(3));
        await repo.saveHabit(a);
        await repo.saveHabit(b);
        expect(repo.getHabits().map((h) => h.id), ['b', 'a']);
        expect(repo.getHabit('b'), b);

        await repo.saveHabit(a.copyWith(name: 'Renamed'));
        expect(repo.getHabit('a')!.name, 'Renamed');

        await repo.deleteHabit('a');
        expect(repo.getHabit('a'), isNull);
        expect(repo.getHabits(), [b]);
      });

      test('completions set / unset / delete per habit', () async {
        await repo.setCompletion('a', DateTime(2026, 1, 3, 18), true);
        await repo.setCompletion('a', d(2026, 1, 1), true);
        await repo.setCompletion('b', d(2026, 1, 1), true);
        await repo.setCompletion('b', d(2026, 1, 1), false);
        final log = repo.getCompletions();
        expect(log.datesFor('a'), [d(2026, 1, 1), d(2026, 1, 3)]);
        expect(log.totalFor('b'), 0);

        final removed = await repo.deleteCompletionsFor('a');
        expect(removed, [d(2026, 1, 1), d(2026, 1, 3)]);
        expect(repo.getCompletions(), const CompletionLog.empty());
      });

      test('watchHabits emits current value then changes', () async {
        final events = <List<Habit>>[];
        final sub = repo.watchHabits().listen(events.add);
        await pumpEventQueue();
        await repo.saveHabit(habit(id: 'x'));
        await pumpEventQueue();
        await sub.cancel();
        expect(events.first, isEmpty);
        expect(events.last.map((h) => h.id), ['x']);
      });

      test('watchCompletions emits current value then changes', () async {
        await repo.setCompletion('a', d(2026, 1, 1), true);
        final events = <CompletionLog>[];
        final sub = repo.watchCompletions().listen(events.add);
        await pumpEventQueue();
        await repo.setCompletion('a', d(2026, 1, 2), true);
        await pumpEventQueue();
        await sub.cancel();
        expect(events.first.totalFor('a'), 1);
        expect(events.last.totalFor('a'), 2);
      });
    });
  }

  test('Hive data survives reopening', () async {
    final repo = await HiveHabitRepository.open(boxPrefix: 'persist_');
    final h = Habit(
      id: 'p',
      name: 'Persist',
      emoji: '💾',
      colorValue: 1,
      schedule: EveryNDaysSchedule(2),
      reminderTime: const ReminderTime(hour: 21, minute: 5),
      createdAt: DateTime(2026, 1, 1, 8),
      startDate: d(2026, 1, 1),
    );
    await repo.saveHabit(h);
    await repo.setCompletion('p', d(2026, 1, 3), true);
    await repo.close();

    final reopened = await HiveHabitRepository.open(boxPrefix: 'persist_');
    expect(reopened.getHabit('p'), h);
    expect(reopened.getCompletions().isCompleted('p', d(2026, 1, 3)), isTrue);
    await reopened.close();
  });
}
