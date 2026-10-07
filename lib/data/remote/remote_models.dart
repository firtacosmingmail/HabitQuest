/// Plain JSON DTOs for the Edge Function resources (shared API contract).
///
/// These are deliberately independent of the local hive models: mapping
/// between the two belongs to the sync layer.
library;

import 'json_utils.dart';

/// A server-side row with last-write-wins metadata.
abstract interface class RemoteEntity {
  String get id;
  DateTime get updatedAt;

  /// Tombstone time, `null` when alive.
  DateTime? get deletedAt;

  Map<String, dynamic> toJson();
}

/// Contract Habit JSON.
class RemoteHabit implements RemoteEntity {
  @override
  final String id;
  final String name;
  final String emoji;

  /// ARGB colour.
  final int color;

  /// The app's `HabitSchedule.toJson()`; the server stores it opaquely.
  final Map<String, dynamic> schedule;

  /// `"HH:mm"` or `null`.
  final String? reminderTime;
  final DateTime createdAt;
  final bool archived;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  const RemoteHabit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    required this.schedule,
    this.reminderTime,
    required this.createdAt,
    this.archived = false,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  factory RemoteHabit.fromJson(Map<String, dynamic> json) => RemoteHabit(
    id: readString(json, 'id'),
    name: readString(json, 'name'),
    emoji: json['emoji'] as String? ?? '',
    color: (json['color'] as num).toInt(),
    schedule: Map<String, dynamic>.from(readObject(json, 'schedule')),
    reminderTime: json['reminderTime'] as String?,
    createdAt: parseTimestamp(json['createdAt'], 'createdAt'),
    archived: json['archived'] as bool? ?? false,
    updatedAt: parseTimestamp(json['updatedAt'], 'updatedAt'),
    deletedAt: parseTimestampOrNull(json['deletedAt'], 'deletedAt'),
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'color': color,
    'schedule': schedule,
    'reminderTime': reminderTime,
    'createdAt': formatTimestamp(createdAt),
    'archived': archived,
    'updatedAt': formatTimestamp(updatedAt),
    'deletedAt': deletedAt == null ? null : formatTimestamp(deletedAt!),
  };

  RemoteHabit copyWith({
    String? name,
    String? emoji,
    int? color,
    Map<String, dynamic>? schedule,
    String? Function()? reminderTime,
    bool? archived,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) => RemoteHabit(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    color: color ?? this.color,
    schedule: schedule ?? this.schedule,
    reminderTime: reminderTime != null ? reminderTime() : this.reminderTime,
    createdAt: createdAt,
    archived: archived ?? this.archived,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is RemoteHabit && _jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(id, updatedAt);

  @override
  String toString() => 'RemoteHabit${toJson()}';
}

/// Contract CheckIn JSON. [id] is always `"<habitId>_<yyyy-MM-dd>"`.
class RemoteCheckIn implements RemoteEntity {
  final String habitId;

  /// Local-midnight date (the app's date convention).
  final DateTime date;
  final bool completed;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  RemoteCheckIn({
    required this.habitId,
    required DateTime date,
    required this.completed,
    required this.updatedAt,
    this.deletedAt,
  }) : date = DateTime(date.year, date.month, date.day);

  /// The contract id for a habit/date pair.
  static String idFor(String habitId, DateTime date) =>
      '${habitId}_${formatDate(date)}';

  @override
  String get id => idFor(habitId, date);

  bool get isDeleted => deletedAt != null;

  factory RemoteCheckIn.fromJson(Map<String, dynamic> json) => RemoteCheckIn(
    habitId: readString(json, 'habitId'),
    date: parseDate(json['date'], 'date'),
    completed: json['completed'] as bool? ?? false,
    updatedAt: parseTimestamp(json['updatedAt'], 'updatedAt'),
    deletedAt: parseTimestampOrNull(json['deletedAt'], 'deletedAt'),
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'habitId': habitId,
    'date': formatDate(date),
    'completed': completed,
    'updatedAt': formatTimestamp(updatedAt),
    'deletedAt': deletedAt == null ? null : formatTimestamp(deletedAt!),
  };

  RemoteCheckIn copyWith({
    bool? completed,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) => RemoteCheckIn(
    habitId: habitId,
    date: date,
    completed: completed ?? this.completed,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is RemoteCheckIn && _jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(id, updatedAt);

  @override
  String toString() => 'RemoteCheckIn${toJson()}';
}

/// Contract GameState JSON: an opaque [state] object plus [updatedAt].
class RemoteGameState {
  final Map<String, dynamic> state;
  final DateTime updatedAt;

  const RemoteGameState({required this.state, required this.updatedAt});

  factory RemoteGameState.fromJson(Map<String, dynamic> json) =>
      RemoteGameState(
        state: Map<String, dynamic>.from(readObject(json, 'state')),
        updatedAt: parseTimestamp(json['updatedAt'], 'updatedAt'),
      );

  Map<String, dynamic> toJson() => {
    'state': state,
    'updatedAt': formatTimestamp(updatedAt),
  };

  @override
  bool operator ==(Object other) =>
      other is RemoteGameState && _jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => updatedAt.hashCode;

  @override
  String toString() => 'RemoteGameState${toJson()}';
}

/// Response of a `GET ?since=` delta pull.
class DeltaPage<T> {
  final List<T> items;

  /// Store this and send it as `since` on the next pull.
  final DateTime serverTime;

  const DeltaPage({required this.items, required this.serverTime});
}

/// Response of an upsert / soft delete: the row as stored afterwards, and
/// whether the write won last-write-wins.
class WriteResult<T> {
  final T item;
  final bool applied;

  const WriteResult({required this.item, required this.applied});
}

/// One entry of a `POST /batch` response (same order as the request).
class BatchItemResult<T> {
  final String id;
  final bool applied;
  final T item;

  const BatchItemResult({
    required this.id,
    required this.applied,
    required this.item,
  });
}

/// Response of `GET /game-state`.
class GameStateSnapshot {
  final RemoteGameState? item;
  final DateTime serverTime;

  const GameStateSnapshot({required this.item, required this.serverTime});
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
