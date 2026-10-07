import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/repositories/hive_habit_repository.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/data/sync/sync_meta.dart';
import 'package:habit_quest/data/sync/sync_queue.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:hive_ce/hive.dart';

import '../../helpers/fixtures.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('habit_quest_sync');
    Hive.init(tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  test('the queue survives an app restart, coalesced', () async {
    var queue = SyncQueue(await HiveStringStore.open('q1'));
    final repo = await HiveHabitRepository.open(
      boxPrefix: 'q1_',
      recorder: queue,
    );
    await repo.saveHabit(habit(id: 'a'));
    await repo.saveHabit(habit(id: 'a', name: 'Renamed'));
    await repo.setCompletion('a', d(2026, 1, 5), true);
    await repo.setCompletion('a', d(2026, 1, 5), false);
    await repo.deleteHabit('a');
    await repo.close();
    await queue.close();

    queue = SyncQueue(await HiveStringStore.open('q1'));
    expect(queue.entries.map((e) => e.key), [
      'checkIn:a|2026-01-05',
      'habit:a',
    ]);
    // New changes still get a newer sequence number after the restart.
    final before = queue.entryFor(SyncEntityType.habit, 'a')!.seq;
    await queue.recordChange(SyncEntityType.habit, 'a');
    expect(queue.entryFor(SyncEntityType.habit, 'a')!.seq, greaterThan(before));

    final reopened = await HiveHabitRepository.open(boxPrefix: 'q1_');
    expect(reopened.getHabit('a'), isNull);
    expect(reopened.getHabitRecord('a')!.isDeleted, isTrue);
    expect(reopened.getCheckIn('a', d(2026, 1, 5))!.completed, isFalse);
    await reopened.close();
    await queue.close();
  });

  test('sync meta (owner, cursors) survives a restart', () async {
    var meta = SyncMeta(await HiveStringStore.open('m1'));
    await meta.setOwner('u1');
    await meta.setHabitsCursor('u1', DateTime.utc(2026, 1, 5, 10));
    await Hive.box<String>('m1').close();
    meta = SyncMeta(await HiveStringStore.open('m1'));
    expect(meta.ownerUserId, 'u1');
    expect(meta.habitsCursor('u1'), DateTime.utc(2026, 1, 5, 10));
  });

  test('game saves are queued, synced saves are not', () async {
    final queue = SyncQueue(MemoryStringStore());
    final repo = await HiveGameRepository.open(
      boxPrefix: 'g1_',
      recorder: queue,
    );
    await repo.saveSynced(const GameState(bestStreakEver: 2));
    expect(queue.isEmpty, isTrue);
    await repo.save(const GameState(bestStreakEver: 3));
    expect(queue.entries.single.key, 'gameState:game');
    await repo.close();
  });

  group('data from the pre-sync version stays readable', () {
    test('habits without updatedAt and boolean check-ins', () async {
      final habits = await Hive.openBox<String>('legacy_habits');
      final legacyHabit = habit(id: 'old').toJson()
        ..remove('updatedAt')
        ..remove('deletedAt');
      await habits.put('old', jsonEncode(legacyHabit));
      await habits.close();
      final completions = await Hive.openBox<bool>('legacy_completions');
      await completions.put('old|2026-01-03', true);
      await completions.put('old|2026-01-04', true);
      await completions.close();

      final migratedAt = DateTime.utc(2026, 2, 1, 12);
      final repo = await HiveHabitRepository.open(
        boxPrefix: 'legacy_',
        now: () => migratedAt,
      );
      final h = repo.getHabit('old')!;
      expect(h.updatedAt, h.createdAt.toUtc());
      expect(h.deletedAt, isNull);
      expect(repo.getCompletions().datesFor('old'), [
        d(2026, 1, 3),
        d(2026, 1, 4),
      ]);
      expect(repo.getCheckIn('old', d(2026, 1, 3))!.updatedAt, migratedAt);
      await repo.close();

      // Migrated once: reopening reads the new format.
      final again = await HiveHabitRepository.open(boxPrefix: 'legacy_');
      expect(again.getCompletions().totalFor('old'), 2);
      expect(again.getCheckIn('old', d(2026, 1, 3))!.updatedAt, migratedAt);
      await again.close();
    });

    test('a game state without updatedAt', () {
      final json = const GameState(bestStreakEver: 4).toJson()
        ..remove('updatedAt');
      final s = GameState.fromJson(json);
      expect(s.bestStreakEver, 4);
      expect(s.updatedAt, isNull);
    });
  });
}
