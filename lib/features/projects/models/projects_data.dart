import 'consistent_action.dart';
import 'plan_task.dart';
import 'project.dart';
import 'session_mark.dart';
import 'target.dart';

/// An immutable snapshot of every VISIBLE projects record.
///
/// Visibility cascades: a record is hidden when it or any ancestor is
/// deleted (project → target → plan task / consistent action → session
/// mark). Archived projects stay visible (filter on `Project.archived`).
///
/// Lists are sorted: projects and targets by `createdAt` (then id), plan
/// tasks by `position` (then `createdAt`, id), actions by `createdAt`.
class ProjectsData {
  final List<Project> projects;
  final List<Target> targets;
  final List<PlanTask> planTasks;
  final List<ConsistentAction> actions;

  /// Visible session marks by `SessionMark.key` (any `attended` value).
  final Map<String, SessionMark> sessionMarks;

  final Map<String, Project> _projectsById;
  final Map<String, Target> _targetsById;
  final Map<String, ConsistentAction> _actionsById;
  final Map<String, PlanTask> _planTasksById;

  ProjectsData._(
    this.projects,
    this.targets,
    this.planTasks,
    this.actions,
    this.sessionMarks,
  )   : _projectsById = {for (final p in projects) p.id: p},
        _targetsById = {for (final t in targets) t.id: t},
        _actionsById = {for (final a in actions) a.id: a},
        _planTasksById = {for (final t in planTasks) t.id: t};

  static final empty = ProjectsData.fromRecords();

  /// Builds a snapshot from raw records (tombstones included); hidden
  /// records are dropped.
  factory ProjectsData.fromRecords({
    Iterable<Project> projects = const [],
    Iterable<Target> targets = const [],
    Iterable<PlanTask> planTasks = const [],
    Iterable<ConsistentAction> actions = const [],
    Iterable<SessionMark> sessionMarks = const [],
  }) {
    final ps = projects.where((p) => !p.isDeleted).toList()
      ..sort((a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id));
    final pIds = {for (final p in ps) p.id};
    final ts = targets
        .where((t) => !t.isDeleted && pIds.contains(t.projectId))
        .toList()
      ..sort((a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id));
    final tIds = {for (final t in ts) t.id};
    final tasks = planTasks
        .where((t) => !t.isDeleted && tIds.contains(t.targetId))
        .toList()
      ..sort((a, b) {
        final c = a.position.compareTo(b.position);
        return c != 0 ? c : _byCreated(a.createdAt, a.id, b.createdAt, b.id);
      });
    final as = actions
        .where((a) => !a.isDeleted && tIds.contains(a.targetId))
        .toList()
      ..sort((a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id));
    final aIds = {for (final a in as) a.id};
    final marks = {
      for (final m in sessionMarks)
        if (m.deletedAt == null && aIds.contains(m.actionId)) m.key: m,
    };
    return ProjectsData._(
      List.unmodifiable(ps),
      List.unmodifiable(ts),
      List.unmodifiable(tasks),
      List.unmodifiable(as),
      Map.unmodifiable(marks),
    );
  }

  static int _byCreated(DateTime a, String aId, DateTime b, String bId) {
    final c = a.compareTo(b);
    return c != 0 ? c : aId.compareTo(bId);
  }

  Project? project(String id) => _projectsById[id];
  Target? target(String id) => _targetsById[id];
  ConsistentAction? action(String id) => _actionsById[id];
  PlanTask? planTask(String id) => _planTasksById[id];

  /// Visible targets by id.
  Map<String, Target> get targetsById => _targetsById;

  List<Target> targetsOf(String projectId) =>
      targets.where((t) => t.projectId == projectId).toList();

  List<PlanTask> planTasksOf(String targetId) =>
      planTasks.where((t) => t.targetId == targetId).toList();

  List<ConsistentAction> actionsOf(String targetId) =>
      actions.where((a) => a.targetId == targetId).toList();

  /// Whether the session of [actionId] on [date] is marked attended.
  bool isAttended(String actionId, DateTime date) =>
      sessionMarks[SessionMark.keyFor(actionId, date)]?.isAttended ?? false;
}
