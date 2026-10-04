import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../data/models/habit_schedule.dart';
import '../../domain/habit_events.dart';
import '../../domain/habit_service.dart';
import '../../domain/recurrence.dart';
import '../../domain/streaks.dart';
import 'achievements.dart';
import 'game_events.dart';
import 'game_profile.dart';
import 'game_repository.dart';
import 'game_rules.dart';
import 'game_state.dart';

/// The gamification engine (pure Dart, no Flutter).
///
/// Listens to [HabitService.completionEvents] and [HabitService.habitChanges]
/// and turns them into XP, levels and achievements.
///
/// Anti-exploit design: every XP grant is recorded in a ledger keyed by what
/// earned it (`habitId|date` for a check-in, `date` for a Perfect Day).
/// Removing a check-in reverses exactly the ledger entry; a key that is
/// already in the ledger never earns again. Toggling a check-in on and off
/// any number of times therefore nets 0 XP.
///
/// Rules:
/// * Check-in: 10 XP + streak bonus (+1 per streak period including the
///   check-in, max +10; 0 if the habit is not scheduled that day).
/// * Perfect Day: +25 XP when every habit due that day is done; re-evaluated
///   whenever check-ins of that day change (check-in, un-check, deleting a
///   habit with its check-ins). Creating / editing / archiving habits never
///   grants or removes XP.
/// * Deleting a habit removes the XP of all its check-ins.
/// * Levels and achievements: see [GameRules] and [achievementCatalog].
///   Achievements and [LevelUp] events are emitted at most once, ever.
class GameEngine {
  final HabitService _service;
  final GameRepository _repository;
  final DateTime Function() _now;

  GameState _state;
  final _events = StreamController<GameEvent>.broadcast();
  final _states = StreamController<GameState>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _pendingSave = Future<void>.value();
  bool _started = false;
  bool _disposed = false;

  GameEngine({
    required HabitService service,
    required GameRepository repository,
    DateTime Function()? now,
  }) : _service = service,
       _repository = repository,
       _now = now ?? DateTime.now,
       _state = repository.load();

  /// Current state.
  GameState get state => _state;

  /// Current state as a UI-friendly profile.
  GameProfile get profile => GameProfile.fromState(_state);

  /// Broadcast stream of celebrations / XP changes.
  Stream<GameEvent> get events => _events.stream;

  /// Broadcast stream of new states (after every change).
  Stream<GameState> get stateChanges => _states.stream;

  bool get isStarted => _started;

  /// Subscribes to the habit service and catches up on habit-count and
  /// streak achievements for existing data (no XP is granted retroactively).
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscriptions
      ..add(_service.completionEvents.listen(handleCompletion))
      ..add(_service.habitChanges.listen(handleHabitChange));

    final tx = _Tx(_state);
    final habits = _service.repository.getHabits();
    final log = _service.repository.getCompletions();
    final today = _service.today;
    for (final h in habits) {
      tx.bestStreakEver = math.max(
        tx.bestStreakEver,
        bestStreak(h, log, today),
      );
    }
    _commit(tx, habits);
  }

  /// Completes when every state change so far has been persisted.
  Future<void> flush() => _pendingSave;

  /// Applies a check-in change. Called from the service stream; public for
  /// tests.
  void handleCompletion(CompletionEvent event) {
    if (_disposed) return;
    final date = dateOnly(event.date);
    final habits = _service.repository.getHabits();
    // Evaluate against the state described by the event, even if later
    // writes already happened (their own events will follow).
    final log = _service.repository.getCompletions().withCompletion(
      event.habitId,
      date,
      event.completed,
    );
    final habit = habits.where((h) => h.id == event.habitId).firstOrNull;
    final tx = _Tx(_state);
    final key = GameState.checkInKey(event.habitId, date);

    if (event.completed) {
      if (habit != null && !tx.checkIns.containsKey(key)) {
        final streak = isScheduledOn(habit, date)
            ? currentStreak(habit, log, date)
            : 0;
        final amount = GameRules.checkInReward(streak);
        tx.checkIns[key] = amount;
        tx.events.add(
          XpGained(
            amount: amount,
            habitId: habit.id,
            reason: XpReason.checkIn,
            date: date,
          ),
        );
      }
    } else {
      final amount = tx.checkIns.remove(key);
      if (amount != null && amount > 0) {
        tx.events.add(
          XpLost(
            amount: amount,
            habitId: event.habitId,
            reason: XpReason.checkIn,
            date: date,
          ),
        );
      }
    }

    for (final d in _affectedDays(habit, date)) {
      _evaluatePerfectDay(tx, d, habits, log);
    }
    if (habit != null) {
      tx.bestStreakEver = math.max(
        tx.bestStreakEver,
        bestStreak(habit, log, _service.today),
      );
    }
    _commit(tx, habits);
  }

  /// Applies a habit lifecycle change. Called from the service stream;
  /// public for tests.
  void handleHabitChange(HabitChangeEvent event) {
    if (_disposed) return;
    final habits = _service.repository.getHabits();
    final tx = _Tx(_state);
    if (event.type == HabitChangeType.created) tx.habitCreated = true;

    if (event.type == HabitChangeType.deleted) {
      final prefix = '${event.habit.id}|';
      final keys = tx.checkIns.keys.where((k) => k.startsWith(prefix)).toList();
      var total = 0;
      for (final k in keys) {
        total += tx.checkIns.remove(k)!;
      }
      if (total > 0) {
        tx.events.add(
          XpLost(
            amount: total,
            habitId: event.habit.id,
            reason: XpReason.habitDeleted,
            date: _service.today,
          ),
        );
      }
      final log = _service.repository.getCompletions();
      final days = {for (final d in event.removedCompletions) dateOnly(d)};
      for (final d in days) {
        _evaluatePerfectDay(tx, d, habits, log);
      }
    }
    _commit(tx, habits);
  }

  /// Days whose Perfect Day status can change when [habit]'s check-in on
  /// [date] changes: the day itself and, for times-per-week habits, the
  /// rest of that ISO week up to today (their due status depends on it).
  Iterable<DateTime> _affectedDays(Habit? habit, DateTime date) sync* {
    yield date;
    if (habit?.schedule is! TimesPerWeekSchedule) return;
    final end = endOfIsoWeek(date);
    final today = _service.today;
    for (
      var d = addDays(date, 1);
      !d.isAfter(end) && !d.isAfter(today);
      d = addDays(d, 1)
    ) {
      yield d;
    }
  }

  void _evaluatePerfectDay(
    _Tx tx,
    DateTime date,
    List<Habit> habits,
    CompletionLog log,
  ) {
    final key = dateKey(date);
    final perfect = isPerfectDay(date, habits, log);
    final granted = tx.perfectDays.containsKey(key);
    if (perfect && !granted) {
      tx.perfectDays[key] = GameRules.perfectDayXp;
      tx.events.add(
        XpGained(
          amount: GameRules.perfectDayXp,
          reason: XpReason.perfectDay,
          date: date,
        ),
      );
    } else if (!perfect && granted) {
      final amount = tx.perfectDays.remove(key)!;
      tx.events.add(
        XpLost(amount: amount, reason: XpReason.perfectDay, date: date),
      );
    }
  }

  void _commit(_Tx tx, List<Habit> habits) {
    final events = tx.events;

    // Level-ups: celebrate only levels never reached before.
    final next = tx.build();
    final level = GameRules.levelForXp(next.xp);
    var maxLevel = next.maxLevelReached;
    if (level > maxLevel) {
      maxLevel = level;
      events.add(
        LevelUp(newLevel: level, title: GameRules.titleForLevel(level)),
      );
    }

    // Achievements (never revoked).
    final unlocked = Map<String, DateTime>.of(next.unlocked);
    final values = {
      AchievementKind.habitsCreated: (tx.habitCreated || habits.isNotEmpty)
          ? 1
          : 0,
      AchievementKind.activeHabits: habits.where((h) => !h.archived).length,
      AchievementKind.totalCheckIns: next.totalCheckIns,
      AchievementKind.streak: next.bestStreakEver,
      AchievementKind.perfectDays: next.perfectDays,
    };
    final now = _now();
    for (final a in achievementCatalog) {
      if (unlocked.containsKey(a.id)) continue;
      if (values[a.kind]! >= a.threshold) {
        unlocked[a.id] = now;
        events.add(AchievementUnlocked(a));
      }
    }

    final newState = next.copyWith(
      unlocked: unlocked,
      maxLevelReached: maxLevel,
    );
    if (newState == _state) return;
    _state = newState;
    _pendingSave = _pendingSave
        .then((_) => _repository.save(newState))
        .catchError((Object e, StackTrace st) {
          developer.log(
            'Failed to save game state',
            name: 'GameEngine',
            error: e,
            stackTrace: st,
          );
        });
    _states.add(newState);
    for (final e in events) {
      _events.add(e);
    }
  }

  /// Stops listening and closes the streams (pending saves still finish).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _pendingSave;
    await _events.close();
    await _states.close();
  }
}

/// Mutable working copy for one engine step.
class _Tx {
  final GameState base;
  final Map<String, int> checkIns;
  final Map<String, int> perfectDays;
  int bestStreakEver;
  bool habitCreated = false;
  final List<GameEvent> events = [];

  _Tx(this.base)
    : checkIns = Map.of(base.checkInLedger),
      perfectDays = Map.of(base.perfectDayLedger),
      bestStreakEver = base.bestStreakEver;

  GameState build() => base.copyWith(
    checkInLedger: Map.unmodifiable(checkIns),
    perfectDayLedger: Map.unmodifiable(perfectDays),
    bestStreakEver: bestStreakEver,
  );
}
