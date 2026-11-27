import '../../../core/utils/dates.dart';
import 'json.dart';

/// A goal's status. ALWAYS set by the user; the app never derives it
/// (not from the plan, the sessions or the deadline).
///
/// JSON: the enum name (`"notStarted"`, `"inProgress"`, `"done"`).
enum GoalStatus {
  notStarted,
  inProgress,
  done;

  /// Unknown values fall back to [notStarted] (forward compatibility).
  static GoalStatus fromJson(Object? v) => GoalStatus.values.firstWhere(
        (s) => s.name == v,
        orElse: () => GoalStatus.notStarted,
      );
}

/// A goal of a [Project] (e.g. "5 videos" by 30 Nov). Owns `PlanTask`s
/// (the plan) and `ConsistentAction`s (text items). Time blocks belong to
/// the project, not to the goal.
class Goal {
  /// UUID v4.
  final String id;

  /// The owning `Project.id`.
  final String projectId;
  final String title;

  /// Date-only (local). Display / reminders only: it does not cut off the
  /// project's time blocks.
  final DateTime deadline;

  /// Manual only; see [GoalStatus].
  final GoalStatus status;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  Goal({
    required this.id,
    required this.projectId,
    required this.title,
    required DateTime deadline,
    this.status = GoalStatus.notStarted,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : deadline = dateOnly(deadline),
        createdAt = createdAt.toUtc(),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc();

  bool get isDeleted => deletedAt != null;
  bool get isDone => status == GoalStatus.done;

  Goal copyWith({
    String? title,
    DateTime? deadline,
    GoalStatus? status,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Goal(
        id: id,
        projectId: projectId,
        title: title ?? this.title,
        deadline: deadline ?? this.deadline,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'deadline': dateKey(deadline),
        'status': status.name,
        'createdAt': formatTimestamp(createdAt),
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        title: json['title'] as String,
        deadline: parseDateKey(json['deadline'] as String),
        status: GoalStatus.fromJson(json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is Goal &&
      other.id == id &&
      other.projectId == projectId &&
      other.title == title &&
      other.deadline == deadline &&
      other.status == status &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
      id, projectId, title, deadline, status, createdAt, deletedAt);

  @override
  String toString() =>
      'Goal($id, $title, due ${dateKey(deadline)}, ${status.name})';
}
