import 'achievements.dart';

/// Why XP changed.
enum XpReason {
  /// A check-in (gain) or its removal (loss).
  checkIn,

  /// A Perfect Day bonus (gain) or its removal (loss).
  perfectDay,

  /// A habit was deleted together with its check-ins (loss).
  habitDeleted,

  /// A plan task was finished (gain) or un-checked (loss).
  planTask,

  /// A work session was marked attended (gain) or un-marked (loss).
  session,

  /// A goal was set to done (gain) or back from done (loss).
  goal,

  /// A project, goal, plan task or time block was deleted with
  /// the XP it held (loss).
  projectItemDeleted,
}

/// Something the UI may want to celebrate (or quietly reflect).
sealed class GameEvent {
  const GameEvent();
}

/// XP was granted.
final class XpGained extends GameEvent {
  final int amount;

  /// The habit that earned it (`null` for a Perfect Day bonus and
  /// projects).
  final String? habitId;

  /// The project the XP belongs to (projects reasons only).
  final String? projectId;
  final XpReason reason;

  /// The calendar day the XP belongs to.
  final DateTime date;

  const XpGained({
    required this.amount,
    required this.reason,
    required this.date,
    this.habitId,
    this.projectId,
  });

  @override
  String toString() => 'XpGained(+$amount, $reason, $habitId)';
}

/// Previously granted XP was taken back (un-check, lost Perfect Day,
/// deleted habit). [amount] is positive.
final class XpLost extends GameEvent {
  final int amount;
  final String? habitId;
  final String? projectId;
  final XpReason reason;
  final DateTime date;

  const XpLost({
    required this.amount,
    required this.reason,
    required this.date,
    this.habitId,
    this.projectId,
  });

  @override
  String toString() => 'XpLost(-$amount, $reason, $habitId)';
}

/// A new highest level was reached (emitted once per level, ever).
final class LevelUp extends GameEvent {
  final int newLevel;
  final String title;

  const LevelUp({required this.newLevel, required this.title});

  @override
  String toString() => 'LevelUp($newLevel, $title)';
}

/// An achievement was unlocked (emitted once per achievement, ever).
final class AchievementUnlocked extends GameEvent {
  final Achievement achievement;

  const AchievementUnlocked(this.achievement);

  @override
  String toString() => 'AchievementUnlocked(${achievement.id})';
}
