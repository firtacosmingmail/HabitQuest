import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/stamps.dart';
import '../data/project_repository.dart';
import '../models/clock_time.dart';
import '../models/consistent_action.dart';
import '../models/goal.dart';
import '../models/plan_task.dart';
import '../models/project.dart';
import '../models/projects_data.dart';
import '../models/session_mark.dart';
import '../models/time_block.dart';
import 'overlap.dart';
import 'project_events.dart';
import 'sessions.dart';

/// Application service for every projects mutation (mirrors
/// `HabitService`). Screens, notifications and the game engine use it
/// through `projectServiceProvider` so events stay consistent.
///
/// * Unknown / deleted ids throw [StateError]; invalid input throws
///   [ArgumentError]; a clashing time block throws
///   [TimeBlockOverlapException] and nothing is saved.
/// * Events fire after the repository write; no event when nothing changed.
/// * Status is never changed automatically.
class ProjectService {
  final ProjectRepository _repository;
  final DateTime Function() _now;
  final String Function() _newId;

  final _changes = StreamController<ProjectChangeEvent>.broadcast();
  final _remoteChanges = StreamController<ProjectChangeEvent>.broadcast();
  final _attendance = StreamController<SessionAttendanceEvent>.broadcast();

  ProjectService(
    this._repository, {
    DateTime Function()? now,
    String Function()? idGenerator,
  })  : _now = now ?? DateTime.now,
        _newId = idGenerator ?? const Uuid().v4;

  ProjectRepository get repository => _repository;

  /// The current visible snapshot.
  ProjectsData get data => _repository.getData();

  /// Today's date according to the injected clock.
  DateTime get today => dateOnly(_now());

  /// Local changes (after persistence).
  Stream<ProjectChangeEvent> get changes => _changes.stream;

  /// Changes that arrived through sync ([applyRemote]) or a local wipe
  /// ([clearLocalData]). Notifications listen to both streams; the game
  /// engine only to local events.
  Stream<ProjectChangeEvent> get remoteChanges => _remoteChanges.stream;

  /// Attended marks set / removed by the user.
  Stream<SessionAttendanceEvent> get attendanceEvents => _attendance.stream;

  // Projects -----------------------------------------------------------------

  Future<Project> createProject({required String name}) async {
    final now = _now();
    final p = Project(
      id: _newId(),
      name: _required(name, 'name'),
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    await _repository.save(ProjectRecords(projects: [p]));
    _emit(ProjectChangeType.created, ProjectEntityKind.project, p);
    return p;
  }

  /// Saves an edited project (name / archived). Emits `archived` /
  /// `unarchived` when the flag changed, else `updated`.
  Future<Project> updateProject(Project edited) async {
    final previous = _project(edited.id);
    final p = edited.copyWith(
      name: _required(edited.name, 'name'),
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (p == previous) return previous;
    await _repository.save(ProjectRecords(projects: [p]));
    final type = previous.archived == p.archived
        ? ProjectChangeType.updated
        : (p.archived ? ProjectChangeType.archived : ProjectChangeType.unarchived);
    _emit(type, ProjectEntityKind.project, p, previous);
    return p;
  }

  Future<Project> renameProject(String id, String name) =>
      updateProject(_project(id).copyWith(name: name));

  Future<Project> archiveProject(String id, {bool archived = true}) =>
      updateProject(_project(id).copyWith(archived: archived));

  /// Soft-deletes the project and all of its goals (with their plan tasks
  /// and consistent actions) and time blocks (session marks are hidden
  /// with their block).
  Future<void> deleteProject(String id) async {
    final p = _project(id);
    final d = data;
    final goals = d.goalsOf(id);
    await _deleteCascade(
      projects: [p],
      goals: goals,
      planTasks: [for (final g in goals) ...d.planTasksOf(g.id)],
      consistentActions: [
        for (final g in goals) ...d.consistentActionsOf(g.id),
      ],
      timeBlocks: d.timeBlocksOf(id),
    );
  }

  // Goals --------------------------------------------------------------------

  Future<Goal> createGoal({
    required String projectId,
    required String title,
    required DateTime deadline,
    GoalStatus status = GoalStatus.notStarted,
  }) async {
    _project(projectId);
    final now = _now();
    final g = Goal(
      id: _newId(),
      projectId: projectId,
      title: _required(title, 'title'),
      deadline: deadline,
      status: status,
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    await _repository.save(ProjectRecords(goals: [g]));
    _emit(ProjectChangeType.created, ProjectEntityKind.goal, g);
    return g;
  }

  /// Saves an edited goal (title, deadline, status). The deadline does not
  /// affect the project's time blocks.
  Future<Goal> updateGoal(Goal edited) async {
    final previous = _goal(edited.id);
    if (edited.projectId != previous.projectId) {
      throw ArgumentError.value(edited.projectId, 'projectId', 'cannot change');
    }
    final g = edited.copyWith(
      title: _required(edited.title, 'title'),
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (g == previous) return previous;
    await _repository.save(ProjectRecords(goals: [g]));
    _emit(ProjectChangeType.updated, ProjectEntityKind.goal, g, previous);
    return g;
  }

  /// Sets the status (manual only).
  Future<Goal> setGoalStatus(String id, GoalStatus status) =>
      updateGoal(_goal(id).copyWith(status: status));

  /// Soft-deletes the goal, its plan tasks and its consistent actions.
  Future<void> deleteGoal(String id) async {
    final g = _goal(id);
    final d = data;
    await _deleteCascade(
      goals: [g],
      planTasks: d.planTasksOf(id),
      consistentActions: d.consistentActionsOf(id),
    );
  }

  // Plan tasks ---------------------------------------------------------------

  /// Adds a task at the end of the goal's plan.
  Future<PlanTask> addPlanTask({
    required String goalId,
    required String title,
    DateTime? deliveryDate,
  }) async {
    _goal(goalId);
    final existing = data.planTasksOf(goalId);
    final position = existing.isEmpty ? 0 : existing.last.position + 1;
    final now = _now();
    final task = PlanTask(
      id: _newId(),
      goalId: goalId,
      title: _required(title, 'title'),
      deliveryDate: deliveryDate,
      position: position,
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    await _repository.save(ProjectRecords(planTasks: [task]));
    _emit(ProjectChangeType.created, ProjectEntityKind.planTask, task);
    return task;
  }

  /// Saves an edited task (title, delivery date, done, position).
  Future<PlanTask> updatePlanTask(PlanTask edited) async {
    final previous = _planTask(edited.id);
    if (edited.goalId != previous.goalId) {
      throw ArgumentError.value(edited.goalId, 'goalId', 'cannot change');
    }
    final task = edited.copyWith(
      title: _required(edited.title, 'title'),
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (task == previous) return previous;
    await _repository.save(ProjectRecords(planTasks: [task]));
    _emit(ProjectChangeType.updated, ProjectEntityKind.planTask, task, previous);
    return task;
  }

  Future<PlanTask> setPlanTaskDone(String id, bool done) =>
      updatePlanTask(_planTask(id).copyWith(done: done));

  /// Reorders a goal's plan: [orderedIds] must be exactly its task ids.
  Future<void> reorderPlanTasks(String goalId, List<String> orderedIds) async {
    _goal(goalId);
    final tasks = {for (final t in data.planTasksOf(goalId)) t.id: t};
    _checkOrder(orderedIds, tasks.keys, 'task');
    final changed = <(PlanTask, PlanTask)>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final before = tasks[orderedIds[i]]!;
      if (before.position == i) continue;
      changed.add((
        before.copyWith(position: i, updatedAt: nextStamp(_now(), before.updatedAt)),
        before,
      ));
    }
    if (changed.isEmpty) return;
    await _repository.save(
        ProjectRecords(planTasks: [for (final c in changed) c.$1]));
    for (final (t, before) in changed) {
      _emit(ProjectChangeType.updated, ProjectEntityKind.planTask, t, before);
    }
  }

  Future<void> deletePlanTask(String id) async {
    final task = _planTask(id);
    await _deleteCascade(planTasks: [task]);
  }

  // Consistent actions (text items of a goal) ---------------------------------

  /// Adds a consistent action at the end of the goal's list.
  Future<ConsistentAction> addConsistentAction({
    required String goalId,
    required String text,
  }) async {
    _goal(goalId);
    final existing = data.consistentActionsOf(goalId);
    final order = existing.isEmpty ? 0 : existing.last.sortOrder + 1;
    final now = _now();
    final a = ConsistentAction(
      id: _newId(),
      goalId: goalId,
      text: _required(text, 'text'),
      sortOrder: order,
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    await _repository.save(ProjectRecords(consistentActions: [a]));
    _emit(ProjectChangeType.created, ProjectEntityKind.consistentAction, a);
    return a;
  }

  /// Saves an edited consistent action (text, sort order).
  Future<ConsistentAction> updateConsistentAction(
      ConsistentAction edited) async {
    final previous = _consistentAction(edited.id);
    if (edited.goalId != previous.goalId) {
      throw ArgumentError.value(edited.goalId, 'goalId', 'cannot change');
    }
    final a = edited.copyWith(
      text: _required(edited.text, 'text'),
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (a == previous) return previous;
    await _repository.save(ProjectRecords(consistentActions: [a]));
    _emit(ProjectChangeType.updated, ProjectEntityKind.consistentAction, a,
        previous);
    return a;
  }

  /// Changes the text of a consistent action.
  Future<ConsistentAction> editConsistentAction(String id, String text) =>
      updateConsistentAction(_consistentAction(id).copyWith(text: text));

  /// Reorders a goal's consistent actions: [orderedIds] must be exactly
  /// its action ids.
  Future<void> reorderConsistentActions(
      String goalId, List<String> orderedIds) async {
    _goal(goalId);
    final items = {for (final a in data.consistentActionsOf(goalId)) a.id: a};
    _checkOrder(orderedIds, items.keys, 'consistent action');
    final changed = <(ConsistentAction, ConsistentAction)>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final before = items[orderedIds[i]]!;
      if (before.sortOrder == i) continue;
      changed.add((
        before.copyWith(
            sortOrder: i, updatedAt: nextStamp(_now(), before.updatedAt)),
        before,
      ));
    }
    if (changed.isEmpty) return;
    await _repository.save(
        ProjectRecords(consistentActions: [for (final c in changed) c.$1]));
    for (final (a, before) in changed) {
      _emit(ProjectChangeType.updated, ProjectEntityKind.consistentAction, a,
          before);
    }
  }

  Future<void> deleteConsistentAction(String id) async {
    final a = _consistentAction(id);
    await _deleteCascade(consistentActions: [a]);
  }

  // Time blocks (of a project) -----------------------------------------------

  /// The blocks (any project) that [block] would clash with if saved. For
  /// live validation in forms.
  List<TimeBlockClash> clashesFor(TimeBlock block) =>
      findTimeBlockClashes(block, data);

  /// Creates a time block on a project. Throws [ArgumentError] when the
  /// end is not after the start (or the end date is before the start
  /// date), and [TimeBlockOverlapException] (nothing saved) when it
  /// overlaps another block of any project.
  Future<TimeBlock> createTimeBlock({
    required String projectId,
    String? label,
    required ClockTime startTime,
    required ClockTime endTime,
    required BlockRecurrence recurrence,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _project(projectId);
    final now = _now();
    final b = TimeBlock(
      id: _newId(),
      projectId: projectId,
      label: label,
      startTime: startTime,
      endTime: endTime,
      recurrence: recurrence,
      startDate: startDate,
      endDate: endDate,
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    _checkOverlap(b);
    await _repository.save(ProjectRecords(timeBlocks: [b]));
    _emit(ProjectChangeType.created, ProjectEntityKind.timeBlock, b);
    return b;
  }

  /// Saves an edited block (label, times, recurrence, start / end date).
  /// Throws [TimeBlockOverlapException] (nothing saved) when the new
  /// schedule overlaps; a label-only edit is never refused.
  Future<TimeBlock> updateTimeBlock(TimeBlock edited) async {
    final previous = _timeBlock(edited.id);
    if (edited.projectId != previous.projectId) {
      throw ArgumentError.value(edited.projectId, 'projectId', 'cannot change');
    }
    final b = edited.copyWith(
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (b == previous) return previous;
    // A label-only edit cannot add a clash; skipping the check lets the user
    // rename a block that already clashes (merged or migrated data).
    final scheduleChanged = b.startTime != previous.startTime ||
        b.endTime != previous.endTime ||
        b.recurrence != previous.recurrence ||
        b.startDate != previous.startDate ||
        b.endDate != previous.endDate;
    if (scheduleChanged) _checkOverlap(b);
    await _repository.save(ProjectRecords(timeBlocks: [b]));
    _emit(ProjectChangeType.updated, ProjectEntityKind.timeBlock, b, previous);
    return b;
  }

  Future<void> deleteTimeBlock(String id) async {
    final b = _timeBlock(id);
    await _deleteCascade(timeBlocks: [b]);
  }

  // Sessions -----------------------------------------------------------------

  bool isAttended(String timeBlockId, DateTime date) =>
      data.isAttended(timeBlockId, date);

  /// Marks the session of [timeBlockId] on [date] attended (or not). No-op
  /// (no event) when unchanged. Throws [ArgumentError] for a future date
  /// or a day without a session of that block, [StateError] for an
  /// unknown block.
  Future<void> setSessionAttended(
    String timeBlockId,
    DateTime date,
    bool attended,
  ) async {
    final b = _timeBlock(timeBlockId);
    final d = dateOnly(date);
    if (d.isAfter(today)) {
      throw ArgumentError.value(date, 'date', 'cannot attend a future session');
    }
    if (!hasSessionOn(b, date: d)) {
      throw ArgumentError.value(
          date, 'date', 'no session of $timeBlockId that day');
    }
    if (isAttended(timeBlockId, d) == attended) return;
    final current = _repository.getSessionMarkRecord(timeBlockId, d);
    final mark = SessionMark(
      timeBlockId: timeBlockId,
      date: d,
      attended: attended,
      updatedAt: nextStamp(_now(), current?.updatedAt),
    );
    await _repository.save(ProjectRecords(sessionMarks: [mark]));
    _attendance.add(SessionAttendanceEvent(
      timeBlockId: timeBlockId,
      projectId: b.projectId,
      date: d,
      attended: attended,
    ));
  }

  /// Flips the attended mark; returns the new state.
  Future<bool> toggleSessionAttended(String timeBlockId, DateTime date) async {
    final next = !isAttended(timeBlockId, date);
    await setSessionAttended(timeBlockId, date, next);
    return next;
  }

  // Sync / maintenance -------------------------------------------------------

  /// Applies records pulled from the server (already resolved by
  /// last-write-wins). No local events and no attendance events (no XP:
  /// the sync engine grants it silently through `GameEngine.reconcileSynced`);
  /// every changed record, session marks included, is announced on
  /// [remoteChanges] so the UI, notifications and calendar refresh.
  Future<void> applyRemote(ProjectRecords records) async {
    if (records.isEmpty) return;
    final before = data;
    final marksBefore = {
      for (final m in records.sessionMarks)
        m.key: _repository.getSessionMarkRecord(m.timeBlockId, m.date),
    };
    await _repository.applyRemote(records);
    void announce(ProjectEntityKind kind, String id, Object record,
        bool deleted, Object? previous) {
      final ProjectChangeType type;
      if (deleted) {
        if (previous == null) return;
        type = ProjectChangeType.deleted;
      } else if (previous == null) {
        type = ProjectChangeType.created;
      } else if (record is Project &&
          previous is Project &&
          record.archived != previous.archived) {
        type = record.archived
            ? ProjectChangeType.archived
            : ProjectChangeType.unarchived;
      } else {
        type = ProjectChangeType.updated;
      }
      _remoteChanges.add(ProjectChangeEvent(
          type: type, kind: kind, record: record, previous: previous));
    }

    for (final r in records.projects) {
      announce(ProjectEntityKind.project, r.id, r, r.isDeleted,
          before.project(r.id));
    }
    for (final r in records.goals) {
      announce(ProjectEntityKind.goal, r.id, r, r.isDeleted, before.goal(r.id));
    }
    for (final r in records.planTasks) {
      announce(ProjectEntityKind.planTask, r.id, r, r.isDeleted,
          before.planTask(r.id));
    }
    for (final r in records.timeBlocks) {
      announce(ProjectEntityKind.timeBlock, r.id, r, r.isDeleted,
          before.timeBlock(r.id));
    }
    for (final r in records.consistentActions) {
      announce(ProjectEntityKind.consistentAction, r.id, r, r.isDeleted,
          before.consistentAction(r.id));
    }
    for (final m in records.sessionMarks) {
      final previous = marksBefore[m.key];
      _remoteChanges.add(ProjectChangeEvent(
          type: m.deletedAt != null
              ? ProjectChangeType.deleted
              : (previous == null
                  ? ProjectChangeType.created
                  : ProjectChangeType.updated),
          kind: ProjectEntityKind.sessionMark,
          record: m,
          previous: previous));
    }
  }

  /// Wipes every local projects record (account switch / deletion).
  /// Announced on [remoteChanges] as deletions so notifications are
  /// cancelled.
  Future<void> clearLocalData() async {
    final d = data;
    await _repository.clearAll();
    void gone(ProjectEntityKind kind, Iterable<Object> records) {
      for (final r in records) {
        _remoteChanges.add(ProjectChangeEvent(
            type: ProjectChangeType.deleted, kind: kind, record: r));
      }
    }

    gone(ProjectEntityKind.timeBlock, d.timeBlocks);
    gone(ProjectEntityKind.consistentAction, d.consistentActions);
    gone(ProjectEntityKind.planTask, d.planTasks);
    gone(ProjectEntityKind.goal, d.goals);
    gone(ProjectEntityKind.project, d.projects);
  }

  Future<void> dispose() async {
    await _changes.close();
    await _remoteChanges.close();
    await _attendance.close();
  }

  // Helpers ------------------------------------------------------------------

  void _checkOverlap(TimeBlock b) {
    final clashes = findTimeBlockClashes(b, data);
    if (clashes.isNotEmpty) throw TimeBlockOverlapException(b, clashes);
  }

  static void _checkOrder(
      List<String> orderedIds, Iterable<String> ids, String what) {
    final set = ids.toSet();
    if (orderedIds.length != set.length ||
        orderedIds.toSet().length != set.length ||
        !orderedIds.every(set.contains)) {
      throw ArgumentError.value(orderedIds, 'orderedIds',
          'must list every $what of the goal exactly once');
    }
  }

  /// Tombstones the records in one write, then emits one `deleted` event
  /// per record, children first.
  Future<void> _deleteCascade({
    List<Project> projects = const [],
    List<Goal> goals = const [],
    List<PlanTask> planTasks = const [],
    List<ConsistentAction> consistentActions = const [],
    List<TimeBlock> timeBlocks = const [],
  }) async {
    final now = _now();
    DateTime stamp(DateTime previous) => nextStamp(now, previous);
    final dp = [
      for (final x in projects)
        x.copyWith(
            updatedAt: stamp(x.updatedAt), deletedAt: () => stamp(x.updatedAt)),
    ];
    final dg = [
      for (final x in goals)
        x.copyWith(
            updatedAt: stamp(x.updatedAt), deletedAt: () => stamp(x.updatedAt)),
    ];
    final dk = [
      for (final x in planTasks)
        x.copyWith(
            updatedAt: stamp(x.updatedAt), deletedAt: () => stamp(x.updatedAt)),
    ];
    final dc = [
      for (final x in consistentActions)
        x.copyWith(
            updatedAt: stamp(x.updatedAt), deletedAt: () => stamp(x.updatedAt)),
    ];
    final db = [
      for (final x in timeBlocks)
        x.copyWith(
            updatedAt: stamp(x.updatedAt), deletedAt: () => stamp(x.updatedAt)),
    ];
    await _repository.save(ProjectRecords(
      projects: dp,
      goals: dg,
      planTasks: dk,
      consistentActions: dc,
      timeBlocks: db,
    ));
    void emitAll(ProjectEntityKind kind, List<Object> after, List<Object> before) {
      for (var i = 0; i < after.length; i++) {
        _emit(ProjectChangeType.deleted, kind, after[i], before[i]);
      }
    }

    emitAll(ProjectEntityKind.timeBlock, db, timeBlocks);
    emitAll(ProjectEntityKind.consistentAction, dc, consistentActions);
    emitAll(ProjectEntityKind.planTask, dk, planTasks);
    emitAll(ProjectEntityKind.goal, dg, goals);
    emitAll(ProjectEntityKind.project, dp, projects);
  }

  void _emit(ProjectChangeType type, ProjectEntityKind kind, Object record,
      [Object? previous]) {
    _changes.add(ProjectChangeEvent(
        type: type, kind: kind, record: record, previous: previous));
  }

  static String _required(String value, String name) {
    final t = value.trim();
    if (t.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
    return t;
  }

  Project _project(String id) =>
      data.project(id) ?? (throw StateError('Unknown project: $id'));

  Goal _goal(String id) =>
      data.goal(id) ?? (throw StateError('Unknown goal: $id'));

  TimeBlock _timeBlock(String id) =>
      data.timeBlock(id) ?? (throw StateError('Unknown time block: $id'));

  ConsistentAction _consistentAction(String id) =>
      data.consistentAction(id) ??
      (throw StateError('Unknown consistent action: $id'));

  PlanTask _planTask(String id) =>
      data.planTask(id) ?? (throw StateError('Unknown plan task: $id'));
}
