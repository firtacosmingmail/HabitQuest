import '../../core/utils/dates.dart';

/// One stored check-in record of a habit on a calendar day, with the
/// last-write-wins metadata needed for sync.
///
/// Un-checking does not delete the record: it is kept with
/// `completed: false` and a fresh [updatedAt] so the un-check syncs too.
/// [deletedAt] marks a tombstone that came from the server.
class CheckIn {
  final String habitId;

  /// Local midnight.
  final DateTime date;
  final bool completed;

  /// Last change (UTC).
  final DateTime updatedAt;

  /// Tombstone (UTC), `null` when alive.
  final DateTime? deletedAt;

  CheckIn({
    required this.habitId,
    required DateTime date,
    required this.completed,
    required DateTime updatedAt,
    DateTime? deletedAt,
  })  : date = dateOnly(date),
        updatedAt = updatedAt.toUtc(),
        deletedAt = deletedAt?.toUtc();

  /// Local storage / queue key: `habitId|yyyy-MM-dd`.
  static String keyFor(String habitId, DateTime date) =>
      '$habitId|${dateKey(date)}';

  /// Splits a [keyFor] key into `(habitId, date)`; `null` if malformed.
  static (String, DateTime)? parseKey(String key) {
    final i = key.lastIndexOf('|');
    if (i <= 0) return null;
    try {
      return (key.substring(0, i), parseDateKey(key.substring(i + 1)));
    } on FormatException {
      return null;
    }
  }

  String get key => keyFor(habitId, date);

  /// Counts as done (completed and not a tombstone).
  bool get isDone => completed && deletedAt == null;

  CheckIn copyWith({
    bool? completed,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      CheckIn(
        habitId: habitId,
        date: date,
        completed: completed ?? this.completed,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'habitId': habitId,
        'date': dateKey(date),
        'completed': completed,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory CheckIn.fromJson(Map<String, dynamic> json) => CheckIn(
        habitId: json['habitId'] as String,
        date: parseDateKey(json['date'] as String),
        completed: json['completed'] as bool? ?? true,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is CheckIn &&
      other.habitId == habitId &&
      other.date == date &&
      other.completed == completed &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode =>
      Object.hash(habitId, date, completed, updatedAt, deletedAt);

  @override
  String toString() =>
      'CheckIn($key, ${completed ? 'done' : 'undone'}, $updatedAt'
      '${deletedAt != null ? ', deleted' : ''})';
}
