import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/utils/dates.dart';
import '../../../core/utils/stamps.dart';
import '../data/project_repository.dart';
import '../models/clock_time.dart';
import '../models/consistent_action.dart';
import '../models/plan_task.dart';
import '../models/project.dart';
import '../models/projects_data.dart';
import '../models/session_mark.dart';
import '../models/target.dart';
import 'overlap.dart';
import 'project_events.dart';
import 'sessions.dart';

/// Application service for every projects mutation (mirrors
/// `HabitService`). Screens, notifications and the game engine use it
/// through `projectServiceProvider` so events stay consistent.
///
/// * Unknown / deleted ids throw [StateError]; invalid input throws
///   [ArgumentError]; a clashing consistent action throws
///   [ActionOverlapException] and nothing is saved.
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

  /// Soft-deletes the project and all of its targets, plan tasks and
  /// consistent actions (session marks are hidden with their action).
  Future<void> deleteProject(String id) async {
    final p = _project(id);
    final d = data;
    final targets = d.targetsOf(id);
    await _deleteCascade(
      projects: [p],
      targets: targets,
      planTasks: [for (final t in targets) ...d.planTasksOf(t.id)],
      actions: [for (final t in targets) ...d.actionsOf(t.id)],
    );
  }

  // Targets ------------------------------------------------------------------

  Future<Target> createTarget({
    required String projectId,
    required String title,
    required DateTime deadline,
    TargetStatus status = TargetStatus.notStarted,
  }) async {
    _project(projectId);
    final now = _now();
    final t = Target(
      id: _newId(),
      projectId: projectId,
      title: _required(title, 'title'),
      deadline: deadline,
      status: status,
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    await _repository.save(ProjectRecords(targets: [t]));
    _emit(ProjectChangeType.created, ProjectEntityKind.target, t);
    return t;
  }

  /// Saves an edited target (title, deadline, status).
  ///
  /// Throws [ActionOverlapException] when the change makes one of its
  /// actions clash with another action that it did not clash with before
  /// (a later deadline, or a status changed away from done).
  Future<Target> updateTarget(Target edited) async {
    final previous = _target(edited.id);
    if (edited.projectId != previous.projectId) {
      throw ArgumentError.value(edited.projectId, 'projectId', 'cannot change');
    }
    final t = edited.copyWith(
      title: _required(edited.title, 'title'),
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (t == previous) return previous;
    if (t.deadline != previous.deadline || t.status != previous.status) {
      final d = data;
      for (final a in d.actionsOf(t.id)) {
        final before = {
          for (final c in findActionClashes(a, previous, d)) c.action.id,
        };
        final added = findActionClashes(a, t, d)
            .where((c) => !before.contains(c.action.id))
            .toList();
        if (added.isNotEmpty) throw ActionOverlapException(a, added);
      }
    }
    await _repository.save(ProjectRecords(targets: [t]));
    _emit(ProjectChangeType.updated, ProjectEntityKind.target, t, previous);
    return t;
  }

  /// Sets the status (manual only). See [updateTarget] for overlaps.
  Future<Target> setTargetStatus(String id, TargetStatus status) =>
      updateTarget(_target(id).copyWith(status: status));

  /// Soft-deletes the target, its plan tasks and its consistent actions.
  Future<void> deleteTarget(String id) async {
    final t = _target(id);
    final d = data;
    await _deleteCascade(
      targets: [t],
      planTasks: d.planTasksOf(id),
      actions: d.actionsOf(id),
    );
  }

  // Plan tasks ---------------------------------------------------------------

  /// Adds a task at the end of the target's plan.
  Future<PlanTask> addPlanTask({
    required String targetId,
    required String title,
    DateTime? deliveryDate,
  }) async {
    _target(targetId);
    final existing = data.planTasksOf(targetId);
    final position = existing.isEmpty ? 0 : existing.last.position + 1;
    final now = _now();
    final task = PlanTask(
      id: _newId(),
      targetId: targetId,
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
    if (edited.targetId != previous.targetId) {
      throw ArgumentError.value(edited.targetId, 'targetId', 'cannot change');
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

  /// Reorders a target's plan: [orderedIds] must be exactly its task ids.
  Future<void> reorderPlanTasks(String targetId, List<String> orderedIds) async {
    _target(targetId);
    final tasks = {for (final t in data.planTasksOf(targetId)) t.id: t};
    if (orderedIds.length != tasks.length ||
        !orderedIds.every(tasks.containsKey)) {
      throw ArgumentError.value(orderedIds, 'orderedIds',
          'must list every task of the target exactly once');
    }
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

  // Consistent actions -------------------------------------------------------

  /// The actions that [action] would clash with if saved on [target]
  /// (default: its stored target). For live validation in forms.
  List<ActionClash> clashesFor(ConsistentAction action, {Target? target}) =>
      findActionClashes(action, target ?? _target(action.targetId), data);

  /// Creates a consistent action. Throws [ArgumentError] when the end is
  /// not after the start, and [ActionOverlapException] (nothing saved) when
  /// it overlaps another action.
  Future<ConsistentAction> createAction({
    required String targetId,
    required ClockTime startTime,
    required ClockTime endTime,
    required ActionRecurrence recurrence,
    DateTime? startDate,
  }) async {
    final target = _target(targetId);
    final now = _now();
    final a = ConsistentAction(
      id: _newId(),
      targetId: targetId,
      startTime: startTime,
      endTime: endTime,
      recurrence: recurrence,
      startDate: startDate,
      createdAt: now,
      updatedAt: now.toUtc(),
    );
    _checkOverlap(a, target);
    await _repository.save(ProjectRecords(actions: [a]));
    _emit(ProjectChangeType.created, ProjectEntityKind.consistentAction, a);
    return a;
  }

  /// Saves an edited action (times, recurrence, start date). Throws
  /// [ActionOverlapException] (nothing saved) when it overlaps.
  Future<ConsistentAction> updateAction(ConsistentAction edited) async {
    final previous = _action(edited.id);
    if (edited.targetId != previous.targetId) {
      throw ArgumentError.value(edited.targetId, 'targetId', 'cannot change');
    }
    final a = edited.copyWith(
      updatedAt: nextStamp(_now(), previous.updatedAt),
      deletedAt: () => null,
    );
    if (a == previous) return previous;
    _checkOverlap(a, _target(a.targetId));
    await _repository.save(ProjectRecords(actions: [a]));
    _emit(ProjectChangeType.updated, ProjectEntityKind.consistentAction, a,
        previous);
    return a;
  }

  Future<void> deleteAction(String id) async {
    final a = _action(id);
    await _deleteCascade(actions: [a]);
  }

  // Sessions -----------------------------------------------------------------

  bool isAttended(String actionId, DateTime date) =>
      data.isAttended(actionId, date);

  /// Marks the session of [actionId] on [date] attended (or not). No-op
  /// (no event) when unchanged. Throws [ArgumentError] for a future date
  /// or a day without a session of that action, [StateError] for an
  /// unknown action.
  Future<void> setSessionAttended(
    String actionId,
    DateTime date,
    bool attended,
  ) async {
    final a = _action(actionId);
    final t = _target(a.targetId);
    final d = dateOnly(date);
    if (d.isAfter(today)) {
      throw ArgumentError.value(date, 'date', 'cannot attend a future session');
    }
    if (!hasSessionOn(a, deadline: t.deadline, date: d)) {
      throw ArgumentError.value(date, 'date', 'no session of $actionId that day');
    }
    if (isAttended(actionId, d) == attended) return;
    final current = _repository.getSessionMarkRecord(actionId, d);
    final mark = SessionMark(
      actionId: actionId,
      date: d,
      attended: attended,
      updatedAt: nextStamp(_now(), current?.updatedAt),
    );
    await _repository.save(ProjectRecords(sessionMarks: [mark]));
    _attendance.add(SessionAttendanceEvent(
      actionId: actionId,
      targetId: t.id,
      projectId: t.projectId,
      date: d,
      attended: attended,
    ));
  }

  /// Flips the attended mark; returns the new state.
  Future<bool> toggleSessionAttended(String actionId, DateTime date) async {
    final next = !isAttended(actionId, date);
    await setSessionAttended(actionId, date, next);
    return next;
  }

  // Sync / maintenance -------------------------------------------------------

  /// Applies records pulled from the server (already resolved by
  /// last-write-wins). No local events and no attendance events (no XP);
  /// changed projects / targets / tasks / actions are announced on
  /// [remoteChanges].
  Future<void> applyRemote(ProjectRecords records) async {
    if (records.isEmpty) return;
    final before = data;
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
    for (final r in records.targets) {
      announce(ProjectEntityKind.target, r.id, r, r.isDeleted,
          before.target(r.id));
    }
    for (final r in records.planTasks) {
      announce(ProjectEntityKind.planTask, r.id, r, r.isDeleted,
          before.planTask(r.id));
    }
    for (final r in records.actions) {
      announce(ProjectEntityKind.consistentAction, r.id, r, r.isDeleted,
          before.action(r.id));
    }
  }

  /// Wipes every local projects record (account switch / deletion).
  /// Announced on [remoteChanges] as deletions so notifications are
  /// cancelled.
  Future<void> clearLocalData() async {
    final d = data;
    await _repository.clearAll();
    for (final a in d.actions) {
      _remoteChanges.add(ProjectChangeEvent(
          type: ProjectChangeType.deleted,
          kind: ProjectEntityKind.consistentAction,
          record: a));
    }
    for (final t in d.planTasks) {
      _remoteChanges.add(ProjectChangeEvent(
          type: ProjectChangeType.deleted,
          kind: ProjectEntityKind.planTask,
          record: t));
    }
    for (final t in d.targets) {
      _remoteChanges.add(ProjectChangeEvent(
          type: ProjectChangeType.deleted,
          kind: ProjectEntityKind.target,
          record: t));
    }
    for (final p in d.projects) {
      _remoteChanges.add(ProjectChangeEvent(
          type: ProjectChangeType.deleted,
          kind: ProjectEntityKind.project,
          record: p));
    }
  }

  Future<void> dispose() async {
    await _changes.close();
    await _remoteChanges.close();
    await _attendance.close();
  }

  // Helpers ------------------------------------------------------------------

  void _checkOverlap(ConsistentAction a, Target target) {
    final clashes = findActionClashes(a, target, data);
    if (clashes.isNotEmpty) throw ActionOverlapException(a, clashes);
  }

  Future<void> _deleteCascade({
    List<Project> projects = const [],
    List<Target> targets = const [],
    List<PlanTask> planTasks = const [],
    List<ConsistentAction> actions = const [],
  }) async {
    final now = _now();
    final dp = [
      for (final x in projects)
        x.copyWith(
            updatedAt: nextStamp(now, x.updatedAt),
            deletedAt: () => nextStamp(now, x.updatedAt)),
    ];
    final dt = [
      for (final x in targets)
        x.copyWith(
            updatedAt: nextStamp(now, x.updatedAt),
            deletedAt: () => nextStamp(now, x.updatedAt)),
    ];
    final dk = [
      for (final x in planTasks)
        x.copyWith(
            updatedAt: nextStamp(now, x.updatedAt),
            deletedAt: () => nextStamp(now, x.updatedAt)),
    ];
    final da = [
      for (final x in actions)
        x.copyWith(
            updatedAt: nextStamp(now, x.updatedAt),
            deletedAt: () => nextStamp(now, x.updatedAt)),
    ];
    await _repository.save(ProjectRecords(
        projects: dp, targets: dt, planTasks: dk, actions: da));
    for (var i = 0; i < da.length; i++) {
      _emit(ProjectChangeType.deleted, ProjectEntityKind.consistentAction,
          da[i], actions[i]);
    }
    for (var i = 0; i < dk.length; i++) {
      _emit(ProjectChangeType.deleted, ProjectEntityKind.planTask, dk[i],
          planTasks[i]);
    }
    for (var i = 0; i < dt.length; i++) {
      _emit(ProjectChangeType.deleted, ProjectEntityKind.target, dt[i],
          targets[i]);
    }
    for (var i = 0; i < dp.length; i++) {
      _emit(ProjectChangeType.deleted, ProjectEntityKind.project, dp[i],
          projects[i]);
    }
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

  Target _target(String id) =>
      data.target(id) ?? (throw StateError('Unknown target: $id'));

  ConsistentAction _action(String id) =>
      data.action(id) ?? (throw StateError('Unknown action: $id'));

  PlanTask _planTask(String id) =>
      data.planTask(id) ?? (throw StateError('Unknown plan task: $id'));
}
