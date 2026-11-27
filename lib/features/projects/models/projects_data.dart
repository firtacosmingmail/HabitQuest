import 'consistent_action.dart';
import 'goal.dart';
import 'plan_task.dart';
import 'project.dart';
import 'session_mark.dart';
import 'time_block.dart';

/// An immutable snapshot of every VISIBLE projects record.
///
/// Visibility cascades: a record is hidden when it or any ancestor is
/// deleted (project → goal → plan task / consistent action; project → time
/// block → session mark). Archived projects stay visible (filter on
/// `Project.archived`).
///
/// Lists are sorted: projects, goals and time blocks by `createdAt` (then
/// id), plan tasks by `position` and consistent actions by `sortOrder`
/// (then `createdAt`, id).
class ProjectsData {
  final List<Project> projects;
  final List<Goal> goals;
  final List<PlanTask> planTasks;
  final List<TimeBlock> timeBlocks;
  final List<ConsistentAction> consistentActions;

  /// Visible session marks by `SessionMark.key` (any `attended` value).
  final Map<String, SessionMark> sessionMarks;

  final Map<String, Project> _projectsById;
  final Map<String, Goal> _goalsById;
  final Map<String, TimeBlock> _timeBlocksById;
  final Map<String, PlanTask> _planTasksById;
  final Map<String, ConsistentAction> _consistentActionsById;

  ProjectsData._(
    this.projects,
    this.goals,
    this.planTasks,
    this.timeBlocks,
    this.consistentActions,
    this.sessionMarks,
  )   : _projectsById = {for (final p in projects) p.id: p},
        _goalsById = {for (final g in goals) g.id: g},
        _timeBlocksById = {for (final b in timeBlocks) b.id: b},
        _planTasksById = {for (final t in planTasks) t.id: t},
        _consistentActionsById = {for (final a in consistentActions) a.id: a};

  static final empty = ProjectsData.fromRecords();

  /// Builds a snapshot from raw records (tombstones included); hidden
  /// records are dropped.
  factory ProjectsData.fromRecords({
    Iterable<Project> projects = const [],
    Iterable<Goal> goals = const [],
    Iterable<PlanTask> planTasks = const [],
    Iterable<TimeBlock> timeBlocks = const [],
    Iterable<ConsistentAction> consistentActions = const [],
    Iterable<SessionMark> sessionMarks = const [],
  }) {
    final ps = projects.where((p) => !p.isDeleted).toList()
      ..sort((a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id));
    final pIds = {for (final p in ps) p.id};
    final gs = goals
        .where((g) => !g.isDeleted && pIds.contains(g.projectId))
        .toList()
      ..sort((a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id));
    final gIds = {for (final g in gs) g.id};
    final tasks = planTasks
        .where((t) => !t.isDeleted && gIds.contains(t.goalId))
        .toList()
      ..sort((a, b) {
        final c = a.position.compareTo(b.position);
        return c != 0 ? c : _byCreated(a.createdAt, a.id, b.createdAt, b.id);
      });
    final cas = consistentActions
        .where((a) => !a.isDeleted && gIds.contains(a.goalId))
        .toList()
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : _byCreated(a.createdAt, a.id, b.createdAt, b.id);
      });
    final bs = timeBlocks
        .where((b) => !b.isDeleted && pIds.contains(b.projectId))
        .toList()
      ..sort((a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id));
    final bIds = {for (final b in bs) b.id};
    final marks = {
      for (final m in sessionMarks)
        if (m.deletedAt == null && bIds.contains(m.timeBlockId)) m.key: m,
    };
    return ProjectsData._(
      List.unmodifiable(ps),
      List.unmodifiable(gs),
      List.unmodifiable(tasks),
      List.unmodifiable(bs),
      List.unmodifiable(cas),
      Map.unmodifiable(marks),
    );
  }

  static int _byCreated(DateTime a, String aId, DateTime b, String bId) {
    final c = a.compareTo(b);
    return c != 0 ? c : aId.compareTo(bId);
  }

  Project? project(String id) => _projectsById[id];
  Goal? goal(String id) => _goalsById[id];
  TimeBlock? timeBlock(String id) => _timeBlocksById[id];
  PlanTask? planTask(String id) => _planTasksById[id];
  ConsistentAction? consistentAction(String id) => _consistentActionsById[id];

  /// Visible goals by id.
  Map<String, Goal> get goalsById => _goalsById;

  List<Goal> goalsOf(String projectId) =>
      goals.where((g) => g.projectId == projectId).toList();

  List<PlanTask> planTasksOf(String goalId) =>
      planTasks.where((t) => t.goalId == goalId).toList();

  List<ConsistentAction> consistentActionsOf(String goalId) =>
      consistentActions.where((a) => a.goalId == goalId).toList();

  List<TimeBlock> timeBlocksOf(String projectId) =>
      timeBlocks.where((b) => b.projectId == projectId).toList();

  /// Whether the session of [timeBlockId] on [date] is marked attended.
  bool isAttended(String timeBlockId, DateTime date) =>
      sessionMarks[SessionMark.keyFor(timeBlockId, date)]?.isAttended ??
      false;
}
