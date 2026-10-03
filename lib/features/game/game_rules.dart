/// Pure game rules: XP amounts, level curve and titles.
library;

import 'dart:math' as math;

/// XP and level constants.
abstract final class GameRules {
  /// Base XP for every check-in.
  static const checkInXp = 10;

  /// Streak bonus: +1 XP per streak period (day, or week for
  /// times-per-week habits), capped at this value.
  static const maxStreakBonus = 10;

  /// Bonus when every habit due on a day is complete.
  static const perfectDayXp = 25;

  /// Streak bonus for a check-in that brings the streak to [streak].
  static int streakBonus(int streak) =>
      streak <= 0 ? 0 : math.min(streak, maxStreakBonus);

  /// Total XP for a check-in that brings the streak to [streak].
  static int checkInReward(int streak) => checkInXp + streakBonus(streak);

  /// XP needed to go from [level] to `level + 1` (100 × level).
  static int xpToNextLevel(int level) => 100 * math.max(1, level);

  /// Total XP at which [level] starts. Level 1 starts at 0; going from n to
  /// n+1 costs 100·n, so level L starts at 50·L·(L−1).
  static int xpAtLevelStart(int level) {
    final l = math.max(1, level);
    return 50 * l * (l - 1);
  }

  /// The level reached with [xp] total XP (≥ 1).
  static int levelForXp(int xp) {
    if (xp <= 0) return 1;
    // Solve 50·L·(L−1) ≤ xp, then correct for floating point rounding.
    var level = ((1 + math.sqrt(1 + xp / 12.5)) / 2).floor();
    if (level < 1) level = 1;
    while (xpAtLevelStart(level + 1) <= xp) {
      level++;
    }
    while (level > 1 && xpAtLevelStart(level) > xp) {
      level--;
    }
    return level;
  }

  /// Title for a level band.
  static String titleForLevel(int level) {
    if (level >= 20) return 'Mythic';
    if (level >= 15) return 'Legend';
    if (level >= 11) return 'Champion';
    if (level >= 8) return 'Hero';
    if (level >= 5) return 'Adventurer';
    if (level >= 3) return 'Seeker';
    return 'Sprout';
  }
}
