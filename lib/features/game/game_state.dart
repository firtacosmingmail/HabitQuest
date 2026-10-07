import '../../core/utils/dates.dart';

/// Persisted game state. Immutable; the engine replaces it on every change.
///
/// XP is never stored as a free-running counter: it is the sum of the two
/// ledgers, so every grant can be reversed exactly and toggling a check-in
/// can never mint XP.
class GameState {
  static const schemaVersion = 1;

  /// XP granted per check-in, keyed by [checkInKey] (`habitId|yyyy-MM-dd`).
  final Map<String, int> checkInLedger;

  /// Perfect Day bonus granted per day, keyed by `yyyy-MM-dd`.
  final Map<String, int> perfectDayLedger;

  /// Unlocked achievement id → unlock time. Never shrinks.
  final Map<String, DateTime> unlocked;

  /// High-water mark of the best streak of any habit.
  final int bestStreakEver;

  /// Highest level ever reached (so re-reaching a level after losing XP
  /// does not celebrate it again).
  final int maxLevelReached;

  /// Last change (UTC), for sync; `null` for a state never changed. Not
  /// part of [==].
  final DateTime? updatedAt;

  const GameState({
    this.checkInLedger = const {},
    this.perfectDayLedger = const {},
    this.unlocked = const {},
    this.bestStreakEver = 0,
    this.maxLevelReached = 1,
    this.updatedAt,
  });

  static const empty = GameState();

  static String checkInKey(String habitId, DateTime date) =>
      '$habitId|${dateKey(date)}';

  /// Total XP (sum of both ledgers).
  int get xp =>
      checkInLedger.values.fold(0, (a, b) => a + b) +
      perfectDayLedger.values.fold(0, (a, b) => a + b);

  /// Check-ins that currently hold XP.
  int get totalCheckIns => checkInLedger.length;

  /// Days that currently hold a Perfect Day bonus.
  int get perfectDays => perfectDayLedger.length;

  GameState copyWith({
    Map<String, int>? checkInLedger,
    Map<String, int>? perfectDayLedger,
    Map<String, DateTime>? unlocked,
    int? bestStreakEver,
    int? maxLevelReached,
    DateTime? updatedAt,
  }) => GameState(
    checkInLedger: checkInLedger ?? this.checkInLedger,
    perfectDayLedger: perfectDayLedger ?? this.perfectDayLedger,
    unlocked: unlocked ?? this.unlocked,
    bestStreakEver: bestStreakEver ?? this.bestStreakEver,
    maxLevelReached: maxLevelReached ?? this.maxLevelReached,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Merges two copies of the same player's state (e.g. this device and the
  /// server) without ever counting an award twice:
  ///
  /// * ledgers: union by key (`habitId|date`, `date`); a key present on both
  ///   sides keeps the larger amount, so it is counted once;
  /// * achievements: union, keeping the earliest unlock time;
  /// * best streak, max level reached, updatedAt: the maximum.
  ///
  /// Grants whose check-in was undone elsewhere are removed afterwards by
  /// the engine's reconciliation against the merged check-ins.
  static GameState merge(GameState a, GameState b) {
    Map<String, int> union(Map<String, int> x, Map<String, int> y) {
      final out = Map<String, int>.of(x);
      y.forEach((k, v) {
        final cur = out[k];
        if (cur == null || v > cur) out[k] = v;
      });
      return Map.unmodifiable(out);
    }

    final unlocked = Map<String, DateTime>.of(a.unlocked);
    b.unlocked.forEach((id, t) {
      final cur = unlocked[id];
      if (cur == null || t.isBefore(cur)) unlocked[id] = t;
    });
    final ua = a.updatedAt;
    final ub = b.updatedAt;
    return GameState(
      checkInLedger: union(a.checkInLedger, b.checkInLedger),
      perfectDayLedger: union(a.perfectDayLedger, b.perfectDayLedger),
      unlocked: Map.unmodifiable(unlocked),
      bestStreakEver: a.bestStreakEver > b.bestStreakEver
          ? a.bestStreakEver
          : b.bestStreakEver,
      maxLevelReached: a.maxLevelReached > b.maxLevelReached
          ? a.maxLevelReached
          : b.maxLevelReached,
      updatedAt: ua == null
          ? ub
          : (ub == null || ua.isAfter(ub) ? ua : ub),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'checkIns': checkInLedger,
    'perfectDays': perfectDayLedger,
    'unlocked': {
      for (final e in unlocked.entries) e.key: e.value.toIso8601String(),
    },
    'bestStreakEver': bestStreakEver,
    'maxLevelReached': maxLevelReached,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    Map<String, int> ints(Object? v) => {
      for (final e in ((v as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    return GameState(
      checkInLedger: ints(json['checkIns']),
      perfectDayLedger: ints(json['perfectDays']),
      unlocked: {
        for (final e in ((json['unlocked'] as Map?) ?? const {}).entries)
          e.key as String: DateTime.parse(e.value as String),
      },
      bestStreakEver: (json['bestStreakEver'] as num?)?.toInt() ?? 0,
      maxLevelReached: (json['maxLevelReached'] as num?)?.toInt() ?? 1,
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameState &&
      _mapEq(other.checkInLedger, checkInLedger) &&
      _mapEq(other.perfectDayLedger, perfectDayLedger) &&
      _mapEq(other.unlocked, unlocked) &&
      other.bestStreakEver == bestStreakEver &&
      other.maxLevelReached == maxLevelReached;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      checkInLedger.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      perfectDayLedger.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(unlocked.keys),
    bestStreakEver,
    maxLevelReached,
  );

  @override
  String toString() =>
      'GameState(xp: $xp, checkIns: $totalCheckIns, '
      'perfectDays: $perfectDays, unlocked: ${unlocked.keys.toList()})';
}

bool _mapEq<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
