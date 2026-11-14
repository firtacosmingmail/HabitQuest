import '../data/project_repository.dart';
import '../models/consistent_action.dart';
import '../models/plan_task.dart';
import '../models/project.dart';
import '../models/target.dart';

enum ProjectChangeType { created, updated, archived, unarchived, deleted }

/// Emitted by `ProjectService` after a project, target, plan task or
/// consistent action was persisted (like `HabitChangeEvent`).
///
/// [kind] is never [ProjectEntityKind.sessionMark] (attendance has its own
/// `SessionAttendanceEvent`). `archived` / `unarchived` only occur for
/// projects. Deleting a parent emits one `deleted` event per deleted
/// record (children first, the parent last).
class ProjectChangeEvent {
  final ProjectChangeType type;
  final ProjectEntityKind kind;

  /// The record after the change (for `deleted`: the tombstone).
  final Object record;

  /// The record before the change (`null` for `created`).
  final Object? previous;

  const ProjectChangeEvent({
    required this.type,
    required this.kind,
    required this.record,
    this.previous,
  });

  /// The record's id.
  String get id => switch (record) {
        Project r => r.id,
        Target r => r.id,
        PlanTask r => r.id,
        ConsistentAction r => r.id,
        _ => throw StateError('Unexpected record $record'),
      };

  Project? get project => record is Project ? record as Project : null;
  Target? get target => record is Target ? record as Target : null;
  PlanTask? get planTask => record is PlanTask ? record as PlanTask : null;
  ConsistentAction? get action =>
      record is ConsistentAction ? record as ConsistentAction : null;

  @override
  String toString() => 'ProjectChangeEvent(${type.name}, ${kind.name}, $id)';
}

/// Emitted by `ProjectService` after the user marked a session attended
/// (or un-marked it). The XP task listens to this (like `CompletionEvent`).
/// Never emitted for data that arrived through sync.
class SessionAttendanceEvent {
  final String actionId;
  final String targetId;
  final String projectId;

  /// Date-only (local).
  final DateTime date;
  final bool attended;

  const SessionAttendanceEvent({
    required this.actionId,
    required this.targetId,
    required this.projectId,
    required this.date,
    required this.attended,
  });

  @override
  bool operator ==(Object other) =>
      other is SessionAttendanceEvent &&
      other.actionId == actionId &&
      other.targetId == targetId &&
      other.projectId == projectId &&
      other.date == date &&
      other.attended == attended;

  @override
  int get hashCode =>
      Object.hash(actionId, targetId, projectId, date, attended);

  @override
  String toString() =>
      'SessionAttendanceEvent($actionId, $date, $attended)';
}
