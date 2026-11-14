import 'dart:async';

import '../../../data/repositories/watch.dart';
import '../../../data/sync/change_recorder.dart';
import '../models/consistent_action.dart';
import '../models/plan_task.dart';
import '../models/project.dart';
import '../models/projects_data.dart';
import '../models/session_mark.dart';
import '../models/target.dart';

/// The five stored projects record kinds.
enum ProjectEntityKind {
  project(SyncEntityType.project),
  target(SyncEntityType.target),
  planTask(SyncEntityType.planTask),
  consistentAction(SyncEntityType.consistentAction),
  sessionMark(SyncEntityType.sessionMark);

  const ProjectEntityKind(this.syncType);

  /// The matching sync queue type.
  final SyncEntityType syncType;
}

/// A batch of projects records to write (tombstones included).
class ProjectRecords {
  final List<Project> projects;
  final List<Target> targets;
  final List<PlanTask> planTasks;
  final List<ConsistentAction> actions;
  final List<SessionMark> sessionMarks;

  const ProjectRecords({
    this.projects = const [],
    this.targets = const [],
    this.planTasks = const [],
    this.actions = const [],
    this.sessionMarks = const [],
  });

  bool get isEmpty =>
      projects.isEmpty &&
      targets.isEmpty &&
      planTasks.isEmpty &&
      actions.isEmpty &&
      sessionMarks.isEmpty;
}

/// Persistence boundary for projects, targets, plan tasks, consistent
/// actions and session marks.
///
/// Implementations: `HiveProjectRepository` (app) and
/// `InMemoryProjectRepository` (tests). UI code goes through
/// `ProjectService` and the providers instead.
///
/// Records are never hard-deleted by local writes: deletion is a tombstone
/// (`deletedAt`) written by the service, hidden from [getData] (with its
/// descendants) but kept in the `getAll*Records` lists for sync.
abstract interface class ProjectRepository {
  /// Snapshot of every visible record (see `ProjectsData`).
  ProjectsData getData();

  /// Emits [getData] immediately, then after every change.
  Stream<ProjectsData> watchData();

  /// Every record, tombstones included (sync).
  List<Project> getAllProjectRecords();
  List<Target> getAllTargetRecords();
  List<PlanTask> getAllPlanTaskRecords();
  List<ConsistentAction> getAllActionRecords();
  List<SessionMark> getAllSessionMarkRecords();

  /// Single records, tombstones included (`null` if unknown).
  Project? getProjectRecord(String id);
  Target? getTargetRecord(String id);
  PlanTask? getPlanTaskRecord(String id);
  ConsistentAction? getActionRecord(String id);
  SessionMark? getSessionMarkRecord(String actionId, DateTime date);

  /// Local write: inserts or replaces [records] (keyed by id / mark key)
  /// in one batch, records each one for sync, then emits once. The caller
  /// stamps `updatedAt` / `deletedAt` (see `ProjectService`).
  Future<void> save(ProjectRecords records);

  /// Writes records that came from the server (already resolved by
  /// last-write-wins) without recording them for upload.
  Future<void> applyRemote(ProjectRecords records);

  /// Removes everything (account switch / account deletion).
  Future<void> clearAll();

  /// Releases resources.
  Future<void> close();
}

/// Shared [ProjectRepository] logic over an in-memory cache of every
/// record. Subclasses persist with [persist]; reads come from the cache.
abstract class CachedProjectRepository implements ProjectRepository {
  CachedProjectRepository({this.recorder});

  /// Notified of local writes (the sync queue); `null` = no sync.
  final ChangeRecorder? recorder;

  final Map<String, Project> projectRecords = {};
  final Map<String, Target> targetRecords = {};
  final Map<String, PlanTask> planTaskRecords = {};
  final Map<String, ConsistentAction> actionRecords = {};
  final Map<String, SessionMark> sessionMarkRecords = {};

  final _changes = StreamController<void>.broadcast(sync: true);
  ProjectsData? _cache;

  /// Persists JSON records of one kind (`null` value = remove the key).
  Future<void> persist(
    ProjectEntityKind kind,
    Map<String, Map<String, dynamic>?> changes,
  );

  Future<void> clearStorage();

  Future<void> closeStorage();

  /// Loads records into the cache (subclass `open` / seeding).
  void cacheRecords(ProjectRecords r) {
    for (final p in r.projects) {
      projectRecords[p.id] = p;
    }
    for (final t in r.targets) {
      targetRecords[t.id] = t;
    }
    for (final t in r.planTasks) {
      planTaskRecords[t.id] = t;
    }
    for (final a in r.actions) {
      actionRecords[a.id] = a;
    }
    for (final m in r.sessionMarks) {
      sessionMarkRecords[m.key] = m;
    }
    _cache = null;
  }

  @override
  ProjectsData getData() => _cache ??= ProjectsData.fromRecords(
        projects: projectRecords.values,
        targets: targetRecords.values,
        planTasks: planTaskRecords.values,
        actions: actionRecords.values,
        sessionMarks: sessionMarkRecords.values,
      );

  @override
  Stream<ProjectsData> watchData() => watchValue(getData, _changes.stream);

  @override
  List<Project> getAllProjectRecords() => projectRecords.values.toList();
  @override
  List<Target> getAllTargetRecords() => targetRecords.values.toList();
  @override
  List<PlanTask> getAllPlanTaskRecords() => planTaskRecords.values.toList();
  @override
  List<ConsistentAction> getAllActionRecords() =>
      actionRecords.values.toList();
  @override
  List<SessionMark> getAllSessionMarkRecords() =>
      sessionMarkRecords.values.toList();

  @override
  Project? getProjectRecord(String id) => projectRecords[id];
  @override
  Target? getTargetRecord(String id) => targetRecords[id];
  @override
  PlanTask? getPlanTaskRecord(String id) => planTaskRecords[id];
  @override
  ConsistentAction? getActionRecord(String id) => actionRecords[id];
  @override
  SessionMark? getSessionMarkRecord(String actionId, DateTime date) =>
      sessionMarkRecords[SessionMark.keyFor(actionId, date)];

  @override
  Future<void> save(ProjectRecords records) async {
    if (records.isEmpty) return;
    final r = recorder;
    if (r != null) {
      for (final (kind, key) in _keys(records)) {
        await r.recordChange(kind.syncType, key);
      }
    }
    await _write(records);
  }

  @override
  Future<void> applyRemote(ProjectRecords records) async {
    if (records.isEmpty) return;
    await _write(records);
  }

  Future<void> _write(ProjectRecords r) async {
    cacheRecords(r);
    if (r.projects.isNotEmpty) {
      await persist(ProjectEntityKind.project,
          {for (final x in r.projects) x.id: x.toJson()});
    }
    if (r.targets.isNotEmpty) {
      await persist(ProjectEntityKind.target,
          {for (final x in r.targets) x.id: x.toJson()});
    }
    if (r.planTasks.isNotEmpty) {
      await persist(ProjectEntityKind.planTask,
          {for (final x in r.planTasks) x.id: x.toJson()});
    }
    if (r.actions.isNotEmpty) {
      await persist(ProjectEntityKind.consistentAction,
          {for (final x in r.actions) x.id: x.toJson()});
    }
    if (r.sessionMarks.isNotEmpty) {
      await persist(ProjectEntityKind.sessionMark,
          {for (final x in r.sessionMarks) x.key: x.toJson()});
    }
    _changed();
  }

  Iterable<(ProjectEntityKind, String)> _keys(ProjectRecords r) sync* {
    for (final x in r.projects) {
      yield (ProjectEntityKind.project, x.id);
    }
    for (final x in r.targets) {
      yield (ProjectEntityKind.target, x.id);
    }
    for (final x in r.planTasks) {
      yield (ProjectEntityKind.planTask, x.id);
    }
    for (final x in r.actions) {
      yield (ProjectEntityKind.consistentAction, x.id);
    }
    for (final x in r.sessionMarks) {
      yield (ProjectEntityKind.sessionMark, x.key);
    }
  }

  @override
  Future<void> clearAll() async {
    projectRecords.clear();
    targetRecords.clear();
    planTaskRecords.clear();
    actionRecords.clear();
    sessionMarkRecords.clear();
    await clearStorage();
    _changed();
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await closeStorage();
  }

  void _changed() {
    _cache = null;
    if (!_changes.isClosed) _changes.add(null);
  }
}

/// Non-persistent [ProjectRepository] for tests and previews.
class InMemoryProjectRepository extends CachedProjectRepository {
  InMemoryProjectRepository({
    ProjectRecords seed = const ProjectRecords(),
    super.recorder,
  }) {
    cacheRecords(seed);
  }

  @override
  Future<void> persist(
    ProjectEntityKind kind,
    Map<String, Map<String, dynamic>?> changes,
  ) async {}

  @override
  Future<void> clearStorage() async {}

  @override
  Future<void> closeStorage() async {}
}
