import '../../../core/utils/dates.dart';
import 'json.dart';

/// The user's "attended" mark on one session (one consistent action on one
/// calendar day). Mirrors `CheckIn`: keyed by `(actionId, date)` so two
/// devices marking the same session converge on one record, and un-marking
/// keeps the record with `attended: false` and a fresh [updatedAt] so the
/// change syncs.
class SessionMark {
  /// The `ConsistentAction.id`.
  final String actionId;

  /// Date-only (local) of the session.
  final DateTime date;
  final bool attended;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  SessionMark({
    required this.actionId,
    required DateTime date,
    required this.attended,
    required DateTime updatedAt,
    DateTime? deletedAt,
  })  : date = dateOnly(date),
        updatedAt = updatedAt.toUtc(),
        deletedAt = deletedAt?.toUtc();

  /// Storage / sync queue key: `actionId|yyyy-MM-dd`.
  static String keyFor(String actionId, DateTime date) =>
      '$actionId|${dateKey(date)}';

  String get key => keyFor(actionId, date);

  /// Counts as attended (attended and not a tombstone).
  bool get isAttended => attended && deletedAt == null;

  SessionMark copyWith({
    bool? attended,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      SessionMark(
        actionId: actionId,
        date: date,
        attended: attended ?? this.attended,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'actionId': actionId,
        'date': dateKey(date),
        'attended': attended,
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory SessionMark.fromJson(Map<String, dynamic> json) => SessionMark(
        actionId: json['actionId'] as String,
        date: parseDateKey(json['date'] as String),
        attended: json['attended'] as bool? ?? true,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is SessionMark &&
      other.actionId == actionId &&
      other.date == date &&
      other.attended == attended &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode =>
      Object.hash(actionId, date, attended, updatedAt, deletedAt);

  @override
  String toString() => 'SessionMark($key, ${attended ? 'attended' : 'not'})';
}
