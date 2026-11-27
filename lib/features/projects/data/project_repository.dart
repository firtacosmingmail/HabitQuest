import 'dart:async';

import '../../../data/repositories/watch.dart';
import '../../../data/sync/change_recorder.dart';
import '../models/consistent_action.dart';
import '../models/goal.dart';
import '../models/plan_task.dart';
import '../models/project.dart';
import '../models/projects_data.dart';
import '../models/session_mark.dart';
import '../models/time_block.dart';

/// The six stored projects record kinds.
enum ProjectEntityKind {
  project(SyncEntityType.project),
  goal(SyncEntityType.goal),
  planTask(SyncEntityType.planTask),
  timeBlock(SyncEntityType.timeBlock),
  consistentAction(SyncEntityType.consistentAction),
  sessionMark(SyncEntityType.sessionMark);

  const ProjectEntityKind(this.syncType);

  /// The matching sync queue type.
  final SyncEntityType syncType;
}

/// A batch of projects records to write (tombstones included).
class ProjectRecords {
  final List<Project> projects;
  final List<Goal> goals;
  final List<PlanTask> planTasks;
  final List<TimeBlock> timeBlocks;
  final List<ConsistentAction> consistentActions;
  final List<SessionMark> sessionMarks;

  const ProjectRecords({
    this.projects = const [],
    this.goals = const [],
    this.planTasks = const [],
    this.timeBlocks = const [],
    this.consistentActions = const [],
    this.sessionMarks = const [],
  });

  bool get isEmpty =>
      projects.isEmpty &&
      goals.isEmpty &&
      planTasks.isEmpty &&
      timeBlocks.isEmpty &&
      consistentActions.isEmpty &&
      sessionMarks.isEmpty;
}

/// Persistence boundary for projects, goals, plan tasks, time blocks,
/// consistent actions and session marks.
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
  List<Goal> getAllGoalRecords();
  List<PlanTask> getAllPlanTaskRecords();
  List<TimeBlock> getAllTimeBlockRecords();
  List<ConsistentAction> getAllConsistentActionRecords();
  List<SessionMark> getAllSessionMarkRecords();

  /// Single records, tombstones included (`null` if unknown).
  Project? getProjectRecord(String id);
  Goal? getGoalRecord(String id);
  PlanTask? getPlanTaskRecord(String id);
  TimeBlock? getTimeBlockRecord(String id);
  ConsistentAction? getConsistentActionRecord(String id);
  SessionMark? getSessionMarkRecord(String timeBlockId, DateTime date);

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
  final Map<String, Goal> goalRecords = {};
  final Map<String, PlanTask> planTaskRecords = {};
  final Map<String, TimeBlock> timeBlockRecords = {};
  final Map<String, ConsistentAction> consistentActionRecords = {};
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
    for (final g in r.goals) {
      goalRecords[g.id] = g;
    }
    for (final t in r.planTasks) {
      planTaskRecords[t.id] = t;
    }
    for (final b in r.timeBlocks) {
      timeBlockRecords[b.id] = b;
    }
    for (final a in r.consistentActions) {
      consistentActionRecords[a.id] = a;
    }
    for (final m in r.sessionMarks) {
      sessionMarkRecords[m.key] = m;
    }
    _cache = null;
  }

  @override
  ProjectsData getData() => _cache ??= ProjectsData.fromRecords(
        projects: projectRecords.values,
        goals: goalRecords.values,
        planTasks: planTaskRecords.values,
        timeBlocks: timeBlockRecords.values,
        consistentActions: consistentActionRecords.values,
        sessionMarks: sessionMarkRecords.values,
      );

  @override
  Stream<ProjectsData> watchData() => watchValue(getData, _changes.stream);

  @override
  List<Project> getAllProjectRecords() => projectRecords.values.toList();
  @override
  List<Goal> getAllGoalRecords() => goalRecords.values.toList();
  @override
  List<PlanTask> getAllPlanTaskRecords() => planTaskRecords.values.toList();
  @override
  List<TimeBlock> getAllTimeBlockRecords() =>
      timeBlockRecords.values.toList();
  @override
  List<ConsistentAction> getAllConsistentActionRecords() =>
      consistentActionRecords.values.toList();
  @override
  List<SessionMark> getAllSessionMarkRecords() =>
      sessionMarkRecords.values.toList();

  @override
  Project? getProjectRecord(String id) => projectRecords[id];
  @override
  Goal? getGoalRecord(String id) => goalRecords[id];
  @override
  PlanTask? getPlanTaskRecord(String id) => planTaskRecords[id];
  @override
  TimeBlock? getTimeBlockRecord(String id) => timeBlockRecords[id];
  @override
  ConsistentAction? getConsistentActionRecord(String id) =>
      consistentActionRecords[id];
  @override
  SessionMark? getSessionMarkRecord(String timeBlockId, DateTime date) =>
      sessionMarkRecords[SessionMark.keyFor(timeBlockId, date)];

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
    if (r.goals.isNotEmpty) {
      await persist(ProjectEntityKind.goal,
          {for (final x in r.goals) x.id: x.toJson()});
    }
    if (r.planTasks.isNotEmpty) {
      await persist(ProjectEntityKind.planTask,
          {for (final x in r.planTasks) x.id: x.toJson()});
    }
    if (r.timeBlocks.isNotEmpty) {
      await persist(ProjectEntityKind.timeBlock,
          {for (final x in r.timeBlocks) x.id: x.toJson()});
    }
    if (r.consistentActions.isNotEmpty) {
      await persist(ProjectEntityKind.consistentAction,
          {for (final x in r.consistentActions) x.id: x.toJson()});
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
    for (final x in r.goals) {
      yield (ProjectEntityKind.goal, x.id);
    }
    for (final x in r.planTasks) {
      yield (ProjectEntityKind.planTask, x.id);
    }
    for (final x in r.timeBlocks) {
      yield (ProjectEntityKind.timeBlock, x.id);
    }
    for (final x in r.consistentActions) {
      yield (ProjectEntityKind.consistentAction, x.id);
    }
    for (final x in r.sessionMarks) {
      yield (ProjectEntityKind.sessionMark, x.key);
    }
  }

  @override
  Future<void> clearAll() async {
    projectRecords.clear();
    goalRecords.clear();
    planTaskRecords.clear();
    timeBlockRecords.clear();
    consistentActionRecords.clear();
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
