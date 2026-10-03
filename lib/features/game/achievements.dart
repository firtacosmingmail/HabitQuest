/// The achievement catalog.
library;

/// What an achievement measures.
enum AchievementKind {
  /// Number of habits ever created (unlocked by the first creation).
  habitsCreated,

  /// Number of non-archived habits.
  activeHabits,

  /// Number of current check-ins that earned XP.
  totalCheckIns,

  /// Best streak of any habit (days, or weeks for times-per-week habits).
  streak,

  /// Number of Perfect Days.
  perfectDays,
}

/// A badge the player can unlock. Once unlocked it stays unlocked.
class Achievement {
  final String id;
  final String name;
  final String description;
  final String emoji;

  /// Shown while the badge is still locked.
  final String hint;
  final AchievementKind kind;

  /// The value of [kind] needed to unlock.
  final int threshold;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.hint,
    required this.kind,
    required this.threshold,
  });

  @override
  bool operator ==(Object other) => other is Achievement && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Achievement($id)';
}

/// Stable achievement ids (persisted; never rename).
abstract final class AchievementIds {
  static const firstHabit = 'first_habit';
  static const firstCheckIn = 'first_check_in';
  static const streak3 = 'streak_3';
  static const streak7 = 'streak_7';
  static const streak30 = 'streak_30';
  static const streak100 = 'streak_100';
  static const checkIns10 = 'check_ins_10';
  static const checkIns50 = 'check_ins_50';
  static const checkIns100 = 'check_ins_100';
  static const checkIns500 = 'check_ins_500';
  static const firstPerfectDay = 'first_perfect_day';
  static const fiveActiveHabits = 'five_active_habits';
}

/// All achievements, in display order.
const List<Achievement> achievementCatalog = [
  Achievement(
    id: AchievementIds.firstHabit,
    name: 'A New Quest',
    description: 'Created your first habit.',
    emoji: '🌱',
    hint: 'Create your first habit.',
    kind: AchievementKind.habitsCreated,
    threshold: 1,
  ),
  Achievement(
    id: AchievementIds.firstCheckIn,
    name: 'First Step',
    description: 'Completed your first check-in.',
    emoji: '👣',
    hint: 'Check in a habit for the first time.',
    kind: AchievementKind.totalCheckIns,
    threshold: 1,
  ),
  Achievement(
    id: AchievementIds.streak3,
    name: 'Warming Up',
    description: 'Reached a 3-day streak.',
    emoji: '🔥',
    hint: 'Keep a habit going 3 times in a row.',
    kind: AchievementKind.streak,
    threshold: 3,
  ),
  Achievement(
    id: AchievementIds.streak7,
    name: 'On Fire',
    description: 'Reached a 7-day streak.',
    emoji: '🚀',
    hint: 'Keep a habit going 7 times in a row.',
    kind: AchievementKind.streak,
    threshold: 7,
  ),
  Achievement(
    id: AchievementIds.streak30,
    name: 'Unstoppable',
    description: 'Reached a 30-day streak.',
    emoji: '⚡',
    hint: 'Keep a habit going 30 times in a row.',
    kind: AchievementKind.streak,
    threshold: 30,
  ),
  Achievement(
    id: AchievementIds.streak100,
    name: 'Centurion',
    description: 'Reached a 100-day streak.',
    emoji: '💯',
    hint: 'Keep a habit going 100 times in a row.',
    kind: AchievementKind.streak,
    threshold: 100,
  ),
  Achievement(
    id: AchievementIds.checkIns10,
    name: 'Getting Started',
    description: 'Completed 10 check-ins.',
    emoji: '✅',
    hint: 'Complete 10 check-ins.',
    kind: AchievementKind.totalCheckIns,
    threshold: 10,
  ),
  Achievement(
    id: AchievementIds.checkIns50,
    name: 'Habit Builder',
    description: 'Completed 50 check-ins.',
    emoji: '🧱',
    hint: 'Complete 50 check-ins.',
    kind: AchievementKind.totalCheckIns,
    threshold: 50,
  ),
  Achievement(
    id: AchievementIds.checkIns100,
    name: 'Triple Digits',
    description: 'Completed 100 check-ins.',
    emoji: '🏅',
    hint: 'Complete 100 check-ins.',
    kind: AchievementKind.totalCheckIns,
    threshold: 100,
  ),
  Achievement(
    id: AchievementIds.checkIns500,
    name: 'Habit Master',
    description: 'Completed 500 check-ins.',
    emoji: '👑',
    hint: 'Complete 500 check-ins.',
    kind: AchievementKind.totalCheckIns,
    threshold: 500,
  ),
  Achievement(
    id: AchievementIds.firstPerfectDay,
    name: 'Perfect Day',
    description: 'Completed every habit due on a day.',
    emoji: '🌟',
    hint: 'Complete every habit due on a single day.',
    kind: AchievementKind.perfectDays,
    threshold: 1,
  ),
  Achievement(
    id: AchievementIds.fiveActiveHabits,
    name: 'Juggler',
    description: 'Had 5 active habits at once.',
    emoji: '🤹',
    hint: 'Have 5 active habits at the same time.',
    kind: AchievementKind.activeHabits,
    threshold: 5,
  ),
];

/// Looks up an achievement by id (`null` if unknown).
Achievement? achievementById(String id) {
  for (final a in achievementCatalog) {
    if (a.id == id) return a;
  }
  return null;
}
