import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/game/achievements.dart';
import 'package:habit_quest/features/game/game_profile.dart';
import 'package:habit_quest/features/game/game_rules.dart';
import 'package:habit_quest/features/game/game_state.dart';

void main() {
  group('XP', () {
    test('check-in reward is 10 + streak bonus capped at +10', () {
      expect(GameRules.checkInReward(0), 10);
      expect(GameRules.checkInReward(1), 11);
      expect(GameRules.checkInReward(5), 15);
      expect(GameRules.checkInReward(10), 20);
      expect(GameRules.checkInReward(11), 20);
      expect(GameRules.checkInReward(365), 20);
      expect(GameRules.perfectDayXp, 25);
    });
  });

  group('levels', () {
    test('level n -> n+1 costs 100*n, level 1 starts at 0', () {
      expect(GameRules.xpAtLevelStart(1), 0);
      expect(GameRules.xpAtLevelStart(2), 100);
      expect(GameRules.xpAtLevelStart(3), 300);
      expect(GameRules.xpAtLevelStart(4), 600);
      expect(GameRules.xpAtLevelStart(5), 1000);
      for (var n = 1; n < 50; n++) {
        expect(
          GameRules.xpAtLevelStart(n + 1) - GameRules.xpAtLevelStart(n),
          100 * n,
        );
        expect(GameRules.xpToNextLevel(n), 100 * n);
      }
    });

    test('levelForXp at thresholds', () {
      expect(GameRules.levelForXp(-5), 1);
      expect(GameRules.levelForXp(0), 1);
      expect(GameRules.levelForXp(99), 1);
      expect(GameRules.levelForXp(100), 2);
      expect(GameRules.levelForXp(299), 2);
      expect(GameRules.levelForXp(300), 3);
      expect(GameRules.levelForXp(18999), 19);
      expect(GameRules.levelForXp(19000), 20);
    });

    test('levelForXp agrees with a linear scan', () {
      var level = 1;
      for (var xp = 0; xp <= 60000; xp += 7) {
        while (GameRules.xpAtLevelStart(level + 1) <= xp) {
          level++;
        }
        expect(GameRules.levelForXp(xp), level, reason: 'xp $xp');
      }
    });

    test('titles by level band', () {
      const expected = {
        1: 'Sprout',
        2: 'Sprout',
        3: 'Seeker',
        4: 'Seeker',
        5: 'Adventurer',
        7: 'Adventurer',
        8: 'Hero',
        10: 'Hero',
        11: 'Champion',
        14: 'Champion',
        15: 'Legend',
        19: 'Legend',
        20: 'Mythic',
        99: 'Mythic',
      };
      expected.forEach((level, title) {
        expect(GameRules.titleForLevel(level), title, reason: 'level $level');
      });
    });
  });

  group('GameProfile', () {
    GameState withXp(int xp) => GameState(checkInLedger: {'x|2026-01-01': xp});

    test('initial profile', () {
      final p = GameProfile.initial;
      expect(p.xp, 0);
      expect(p.level, 1);
      expect(p.xpIntoLevel, 0);
      expect(p.xpForNextLevel, 100);
      expect(p.progress, 0);
      expect(p.title, 'Sprout');
      expect(p.unlockedAchievements, isEmpty);
    });

    test('progress into a level', () {
      final p = GameProfile.fromState(withXp(450));
      expect(p.level, 3);
      expect(p.xpIntoLevel, 150);
      expect(p.xpForNextLevel, 300);
      expect(p.progress, closeTo(0.5, 1e-9));
      expect(p.title, 'Seeker');
    });

    test('xp sums both ledgers; stats come from the state', () {
      final s = GameState(
        checkInLedger: const {'a|2026-01-01': 11, 'b|2026-01-01': 12},
        perfectDayLedger: const {'2026-01-01': 25},
        unlocked: {
          AchievementIds.firstPerfectDay: DateTime(2026, 1, 2),
          AchievementIds.firstCheckIn: DateTime(2026, 1, 1),
        },
        bestStreakEver: 4,
      );
      final p = GameProfile.fromState(s);
      expect(p.xp, 48);
      expect(
        p.stats,
        const GameStats(totalCheckIns: 2, bestStreakEver: 4, perfectDays: 1),
      );
      // Catalog order, with timestamps.
      expect(p.unlockedAchievements.map((u) => u.achievement.id), [
        AchievementIds.firstCheckIn,
        AchievementIds.firstPerfectDay,
      ]);
      expect(p.unlockedAt(AchievementIds.firstCheckIn), DateTime(2026, 1, 1));
      expect(p.isUnlocked(AchievementIds.streak3), isFalse);
    });
  });

  test('catalog: 12 achievements with unique ids and full metadata', () {
    expect(achievementCatalog, hasLength(12));
    expect(achievementCatalog.map((a) => a.id).toSet(), hasLength(12));
    for (final a in achievementCatalog) {
      expect(a.name, isNotEmpty);
      expect(a.description, isNotEmpty);
      expect(a.emoji, isNotEmpty);
      expect(a.hint, isNotEmpty);
      expect(achievementById(a.id), same(a));
    }
    expect(achievementById('nope'), isNull);
  });
}
