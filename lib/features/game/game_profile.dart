import 'achievements.dart';
import 'game_rules.dart';
import 'game_state.dart';

/// Stats for the Quest screen.
class GameStats {
  /// Check-ins that currently hold XP.
  final int totalCheckIns;

  /// Best streak of any habit, ever (high-water mark).
  final int bestStreakEver;

  /// Number of Perfect Days.
  final int perfectDays;

  const GameStats({
    required this.totalCheckIns,
    required this.bestStreakEver,
    required this.perfectDays,
  });

  @override
  bool operator ==(Object other) =>
      other is GameStats &&
      other.totalCheckIns == totalCheckIns &&
      other.bestStreakEver == bestStreakEver &&
      other.perfectDays == perfectDays;

  @override
  int get hashCode => Object.hash(totalCheckIns, bestStreakEver, perfectDays);

  @override
  String toString() =>
      'GameStats(checkIns: $totalCheckIns, '
      'bestStreak: $bestStreakEver, perfectDays: $perfectDays)';
}

/// An unlocked achievement with its unlock time.
class UnlockedAchievement {
  final Achievement achievement;
  final DateTime unlockedAt;

  const UnlockedAchievement(this.achievement, this.unlockedAt);

  @override
  bool operator ==(Object other) =>
      other is UnlockedAchievement &&
      other.achievement == achievement &&
      other.unlockedAt == unlockedAt;

  @override
  int get hashCode => Object.hash(achievement, unlockedAt);
}

/// Read-only view of the player's progress for the UI.
class GameProfile {
  final int xp;
  final int level;

  /// XP earned since the current level started.
  final int xpIntoLevel;

  /// XP needed to go from [level] to the next level (100 × level).
  final int xpForNextLevel;
  final String title;

  /// Unlocked achievements in catalog order.
  final List<UnlockedAchievement> unlockedAchievements;
  final GameStats stats;

  const GameProfile({
    required this.xp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.title,
    required this.unlockedAchievements,
    required this.stats,
  });

  factory GameProfile.fromState(GameState state) {
    final xp = state.xp;
    final level = GameRules.levelForXp(xp);
    return GameProfile(
      xp: xp,
      level: level,
      xpIntoLevel: xp - GameRules.xpAtLevelStart(level),
      xpForNextLevel: GameRules.xpToNextLevel(level),
      title: GameRules.titleForLevel(level),
      unlockedAchievements: [
        for (final a in achievementCatalog)
          if (state.unlocked[a.id] case final at?) UnlockedAchievement(a, at),
      ],
      stats: GameStats(
        totalCheckIns: state.totalCheckIns,
        bestStreakEver: state.bestStreakEver,
        perfectDays: state.perfectDays,
      ),
    );
  }

  static final initial = GameProfile.fromState(GameState.empty);

  /// Progress towards the next level, 0..1.
  double get progress =>
      xpForNextLevel == 0 ? 0 : (xpIntoLevel / xpForNextLevel).clamp(0.0, 1.0);

  bool isUnlocked(String achievementId) =>
      unlockedAchievements.any((u) => u.achievement.id == achievementId);

  DateTime? unlockedAt(String achievementId) {
    for (final u in unlockedAchievements) {
      if (u.achievement.id == achievementId) return u.unlockedAt;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! GameProfile ||
        other.xp != xp ||
        other.stats != stats ||
        other.unlockedAchievements.length != unlockedAchievements.length) {
      return false;
    }
    for (var i = 0; i < unlockedAchievements.length; i++) {
      if (other.unlockedAchievements[i] != unlockedAchievements[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(xp, stats, Object.hashAll(unlockedAchievements));

  @override
  String toString() =>
      'GameProfile(xp: $xp, level: $level ($title), $xpIntoLevel/$xpForNextLevel)';
}
