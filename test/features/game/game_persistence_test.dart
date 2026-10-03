import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/game/achievements.dart';
import 'package:habit_quest/features/game/game_engine.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:hive_ce/hive.dart';

import '../../helpers/fixtures.dart';

void main() {
  late Directory tmp;
  var n = 0;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('habit_quest_game');
    Hive.init(tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  final sample = GameState(
    checkInLedger: const {'a|2026-01-04': 11, 'b|2026-01-05': 20},
    perfectDayLedger: const {'2026-01-05': 25},
    unlocked: {
      AchievementIds.firstCheckIn: DateTime(2026, 1, 4, 9, 30),
      AchievementIds.firstPerfectDay: DateTime(2026, 1, 5, 21),
    },
    bestStreakEver: 12,
    maxLevelReached: 2,
  );

  test('JSON round-trip', () {
    expect(GameState.fromJson(sample.toJson()), sample);
    expect(GameState.fromJson(const {}), GameState.empty);
  });

  test('Hive round-trip across close/reopen', () async {
    final prefix = 'p${n++}_';
    final repo = await HiveGameRepository.open(boxPrefix: prefix);
    expect(repo.load(), GameState.empty);
    await repo.save(sample);
    await repo.close();

    final reopened = await HiveGameRepository.open(boxPrefix: prefix);
    addTearDown(reopened.close);
    final loaded = reopened.load();
    expect(loaded, sample);
    expect(loaded.xp, 56);
    expect(
      loaded.unlocked[AchievementIds.firstCheckIn],
      DateTime(2026, 1, 4, 9, 30),
    );
  });

  test('corrupt data loads as an empty state', () async {
    final prefix = 'p${n++}_';
    final box = await Hive.openBox<String>(
      '$prefix${HiveGameRepository.boxName}',
    );
    await box.put(HiveGameRepository.stateKey, '{not json');
    await box.close();
    final repo = await HiveGameRepository.open(boxPrefix: prefix);
    addTearDown(repo.close);
    expect(repo.load(), GameState.empty);
  });

  test(
    'engine state survives a restart on Hive; un-check uses the ledger',
    () async {
      final prefix = 'p${n++}_';
      final habits = InMemoryHabitRepository(habits: [habit(id: 'a')]);
      final service = HabitService(habits, now: () => DateTime(2026, 1, 5, 8));

      final repo1 = await HiveGameRepository.open(boxPrefix: prefix);
      final engine1 = GameEngine(service: service, repository: repo1)..start();
      await service.setCompletion('a', d(2026, 1, 5), true);
      await pumpEventQueue();
      await engine1.dispose();
      await repo1.close();

      final repo2 = await HiveGameRepository.open(boxPrefix: prefix);
      addTearDown(repo2.close);
      final engine2 = GameEngine(service: service, repository: repo2)..start();
      addTearDown(engine2.dispose);
      expect(engine2.state.xp, 11 + 25);
      expect(
        engine2.state.unlocked.keys,
        contains(AchievementIds.firstCheckIn),
      );

      await service.setCompletion('a', d(2026, 1, 5), false);
      await pumpEventQueue();
      await engine2.flush();
      expect(engine2.state.xp, 0);
      expect(repo2.load().xp, 0);
      // Achievements are kept.
      expect(repo2.load().unlocked.keys, contains(AchievementIds.firstCheckIn));
    },
  );
}
