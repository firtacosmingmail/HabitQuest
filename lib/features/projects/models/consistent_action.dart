import 'json.dart';

/// A CONSISTENT ACTION of a goal: just a line of text the user wants to
/// keep doing (e.g. "Post one short a day"). Ordered by [sortOrder]. No
/// time, no tick-off, no XP (time blocks live on the project).
class ConsistentAction {
  /// UUID v4.
  final String id;

  /// The owning `Goal.id`.
  final String goalId;

  /// Non-empty (trimmed by `ProjectService`).
  final String text;

  /// Sort order within the goal (ascending; ties by createdAt, id).
  final int sortOrder;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  ConsistentAction({
    required this.id,
    required this.goalId,
    required this.text,
    this.sortOrder = 0,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : createdAt = createdAt.toUtc(),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc();

  bool get isDeleted => deletedAt != null;

  ConsistentAction copyWith({
    String? text,
    int? sortOrder,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      ConsistentAction(
        id: id,
        goalId: goalId,
        text: text ?? this.text,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'goalId': goalId,
        'text': text,
        'sortOrder': sortOrder,
        'createdAt': formatTimestamp(createdAt),
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory ConsistentAction.fromJson(Map<String, dynamic> json) =>
      ConsistentAction(
        id: json['id'] as String,
        goalId: json['goalId'] as String,
        text: json['text'] as String,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is ConsistentAction &&
      other.id == id &&
      other.goalId == goalId &&
      other.text == text &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode =>
      Object.hash(id, goalId, text, sortOrder, createdAt, deletedAt);

  @override
  String toString() => 'ConsistentAction($id, $text)';
}
