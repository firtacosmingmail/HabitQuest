import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/app.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/game/achievements.dart';
import 'package:habit_quest/features/game/game_events.dart';
import 'package:habit_quest/features/game/game_providers.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  test('profile, events and catalog providers', () async {
    final gameRepo = InMemoryGameRepository(
      GameState(checkInLedger: const {'seed|2025-01-01': 90}),
    );
    final c = ProviderContainer(
      overrides: [
        habitRepositoryProvider.overrideWithValue(
          InMemoryHabitRepository(
            habits: [
              habit(id: 'a'),
              habit(id: 'b'),
            ],
          ),
        ),
        clockProvider.overrideWithValue(() => DateTime(2026, 1, 5, 9)),
        gameRepositoryProvider.overrideWithValue(gameRepo),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(achievementsCatalogProvider), achievementCatalog);

    final events = <GameEvent>[];
    c.read(gameEventsProvider).listen(events.add);
    final profiles = [];
    c.listen(
      gameProfileProvider,
      (_, next) => profiles.add(next),
      fireImmediately: true,
    );

    var profile = c.read(gameProfileProvider);
    expect(profile.xp, 90);
    expect(profile.level, 1);
    expect(profile.progress, closeTo(0.9, 1e-9));

    final service = c.read(habitServiceProvider);
    await service.setCompletion('a', d(2026, 1, 5), true);
    await service.setCompletion('b', d(2026, 1, 5), true);
    await pumpEventQueue();

    profile = c.read(gameProfileProvider);
    expect(profile.xp, 90 + 11 + 11 + 25);
    expect(profile.level, 2);
    expect(profile.xpIntoLevel, 37);
    expect(profile.xpForNextLevel, 200);
    expect(profile.title, 'Sprout');
    expect(profile.stats.totalCheckIns, 3);
    expect(profile.stats.perfectDays, 1);
    expect(profile.isUnlocked(AchievementIds.firstPerfectDay), isTrue);
    expect(
      profile.unlockedAt(AchievementIds.firstPerfectDay),
      DateTime(2026, 1, 5, 9),
    );
    expect(profiles.length, greaterThan(1));

    expect(events.whereType<LevelUp>().single.newLevel, 2);
    // Both writes land before the (async) events are handled, so the bonus
    // may be granted while handling either event; only the set matters.
    expect(
      events.whereType<XpGained>().map((e) => e.amount),
      unorderedEquals([11, 11, 25]),
    );
    expect(
      events.whereType<AchievementUnlocked>().map((e) => e.achievement.id),
      contains(AchievementIds.firstPerfectDay),
    );
    // Persisted.
    await c.read(gameEngineProvider).flush();
    expect(gameRepo.load().xp, 137);
  });

  testWidgets('the app starts the game engine at launch', (tester) async {
    final c = await pumpHabitQuestApp(
      tester,
      repository: InMemoryHabitRepository(habits: [habit(id: 'a')]),
      clock: () => DateTime(2026, 1, 5, 9),
    );
    expect(find.byType(HabitQuestApp), findsOneWidget);
    final engine = c.read(gameEngineProvider);
    expect(engine.isStarted, isTrue);
    await tester.runAsync(() async {
      await c
          .read(habitServiceProvider)
          .setCompletion('a', d(2026, 1, 5), true);
      await pumpEventQueue();
    });
    expect(engine.state.xp, 36);
  });
}
