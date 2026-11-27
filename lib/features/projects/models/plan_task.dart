import '../../../core/utils/dates.dart';
import 'json.dart';

/// A task of a goal's PLAN (e.g. "Write script 1"). Checked off by the
/// user.
class PlanTask {
  /// UUID v4.
  final String id;

  /// The owning `Goal.id`.
  final String goalId;
  final String title;

  /// Optional delivery date (date-only, local).
  final DateTime? deliveryDate;
  final bool done;

  /// Sort order within the goal's plan (ascending; ties by createdAt).
  final int position;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  PlanTask({
    required this.id,
    required this.goalId,
    required this.title,
    DateTime? deliveryDate,
    this.done = false,
    this.position = 0,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : deliveryDate = deliveryDate == null ? null : dateOnly(deliveryDate),
        createdAt = createdAt.toUtc(),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc();

  bool get isDeleted => deletedAt != null;

  PlanTask copyWith({
    String? title,
    DateTime? Function()? deliveryDate,
    bool? done,
    int? position,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      PlanTask(
        id: id,
        goalId: goalId,
        title: title ?? this.title,
        deliveryDate:
            deliveryDate != null ? deliveryDate() : this.deliveryDate,
        done: done ?? this.done,
        position: position ?? this.position,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'goalId': goalId,
        'title': title,
        'deliveryDate': deliveryDate == null ? null : dateKey(deliveryDate!),
        'done': done,
        'position': position,
        'createdAt': formatTimestamp(createdAt),
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory PlanTask.fromJson(Map<String, dynamic> json) => PlanTask(
        id: json['id'] as String,
        goalId: json['goalId'] as String,
        title: json['title'] as String,
        deliveryDate: json['deliveryDate'] == null
            ? null
            : parseDateKey(json['deliveryDate'] as String),
        done: json['done'] as bool? ?? false,
        position: (json['position'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is PlanTask &&
      other.id == id &&
      other.goalId == goalId &&
      other.title == title &&
      other.deliveryDate == deliveryDate &&
      other.done == done &&
      other.position == position &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, goalId, title, deliveryDate, done,
      position, createdAt, deletedAt);

  @override
  String toString() => 'PlanTask($id, $title${done ? ', done' : ''})';
}
