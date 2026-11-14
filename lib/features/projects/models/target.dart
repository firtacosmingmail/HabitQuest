import '../../../core/utils/dates.dart';
import 'json.dart';

/// A target's status. ALWAYS set by the user; the app never derives it
/// (not from the plan, the sessions or the deadline).
///
/// JSON: the enum name (`"notStarted"`, `"inProgress"`, `"done"`).
enum TargetStatus {
  notStarted,
  inProgress,
  done;

  /// Unknown values fall back to [notStarted] (forward compatibility).
  static TargetStatus fromJson(Object? v) => TargetStatus.values.firstWhere(
        (s) => s.name == v,
        orElse: () => TargetStatus.notStarted,
      );
}

/// A target of a [Project] (e.g. "5 videos" by 30 Nov). Owns `PlanTask`s
/// (the plan) and `ConsistentAction`s (recurring time blocks).
class Target {
  /// UUID v4.
  final String id;

  /// The owning `Project.id`.
  final String projectId;
  final String title;

  /// Date-only (local). Sessions of the target's consistent actions run up
  /// to and including this day.
  final DateTime deadline;

  /// Manual only; see [TargetStatus].
  final TargetStatus status;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last change (UTC), last-write-wins.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  Target({
    required this.id,
    required this.projectId,
    required this.title,
    required DateTime deadline,
    this.status = TargetStatus.notStarted,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : deadline = dateOnly(deadline),
        createdAt = createdAt.toUtc(),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc();

  bool get isDeleted => deletedAt != null;
  bool get isDone => status == TargetStatus.done;

  Target copyWith({
    String? title,
    DateTime? deadline,
    TargetStatus? status,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Target(
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

  factory Target.fromJson(Map<String, dynamic> json) => Target(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        title: json['title'] as String,
        deadline: parseDateKey(json['deadline'] as String),
        status: TargetStatus.fromJson(json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      other is Target &&
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
      'Target($id, $title, due ${dateKey(deadline)}, ${status.name})';
}
