/// One-time conversion of the local projects data written before the
/// Projects rework (local schema v1 → v2, docs/PROJECTS.md "Local data
/// migration"):
///
/// * box `project_targets` → `project_goals` (same JSON, same ids);
/// * box `project_actions` (consistent actions of a target) →
///   `project_time_blocks`: `targetId` is replaced by the target's
///   `projectId`, `label` = the target's title, `endDate` = `null`
///   (open-ended), and a block whose target is deleted inherits the
///   target's `deletedAt` (it would otherwise come back to life now that
///   blocks hang off the project). `updatedAt` is kept, so the result is
///   identical to the server migration's (`20261127120000_goals_time_blocks.sql`);
/// * `project_plan_tasks`: `targetId` → `goalId`;
/// * `project_session_marks`: `actionId` → `timeBlockId` (keys unchanged:
///   a time block keeps its old action id, so marks stay attached);
/// * `sync_queue`: pending `target:<id>` entries become `goal:<id>` and
///   `consistentAction:<id>` (the old time blocks) become `timeBlock:<id>`;
/// * `sync_meta`: the Projects pull cursors are reset (full pull of the
///   renamed resources on the next sync).
///
/// Works on raw JSON (not the models) through [StringStore]s, so it is
/// testable in memory. Idempotent: guarded by `schemaVersion` in the
/// `projects_meta` box, written last; every step is also safe to re-run
/// after a crash (old entries are removed only after their copies are
/// written).
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:hive_ce/hive.dart';

import '../../../data/sync/string_store.dart';

/// The current local projects schema.
const projectsSchemaVersion = 2;

/// The stores the migration reads and writes.
class ProjectsStorageStores {
  /// `projects_meta`: holds `schemaVersion`.
  final StringStore meta;
  final StringStore oldTargets;
  final StringStore oldActions;
  final StringStore goals;
  final StringStore planTasks;
  final StringStore timeBlocks;
  final StringStore sessionMarks;

  /// The sync queue box (`null`: no sync, e.g. tests).
  final StringStore? syncQueue;

  /// The sync meta box (`null`: no sync).
  final StringStore? syncMeta;

  const ProjectsStorageStores({
    required this.meta,
    required this.oldTargets,
    required this.oldActions,
    required this.goals,
    required this.planTasks,
    required this.timeBlocks,
    required this.sessionMarks,
    this.syncQueue,
    this.syncMeta,
  });
}

/// The Projects function names whose pull cursors are reset (old and new).
const _cursorNames = [
  'projects',
  'targets',
  'goals',
  'plan-tasks',
  'time-blocks',
  'consistent-actions',
  'session-marks',
];

const _schemaKey = 'schemaVersion';

/// Whether the stored schema is already current.
bool projectsStorageIsCurrent(StringStore meta) =>
    int.tryParse(meta.get(_schemaKey) ?? '') == projectsSchemaVersion;

/// Runs the v1 → v2 conversion unless already done. Returns whether it ran.
Future<bool> migrateProjectsStorage(ProjectsStorageStores s) async {
  if (projectsStorageIsCurrent(s.meta)) return false;

  // Targets → goals (copy first; the old entries are removed at the end).
  final targets = <String, Map<String, dynamic>>{};
  for (final key in s.oldTargets.keys) {
    final json = _decode(s.oldTargets, key);
    if (json == null) continue;
    targets[key] = json;
    await s.goals.put(key, jsonEncode(json));
  }

  // Consistent actions (time blocks of a target) → project time blocks.
  for (final key in s.oldActions.keys) {
    final json = _decode(s.oldActions, key);
    if (json == null) continue;
    final targetId = json['targetId'];
    final target = targets[targetId] ??
        (targetId is String ? _decode(s.goals, targetId) : null);
    final projectId = target?['projectId'];
    if (target == null || projectId is! String) {
      developer.log('Dropping time block $key: unknown target $targetId',
          name: 'ProjectsMigration');
      continue;
    }
    final title = target['title'];
    final block = <String, dynamic>{
      'id': json['id'],
      'projectId': projectId,
      'label': title is String && title.trim().isNotEmpty ? title.trim() : null,
      'startTime': json['startTime'],
      'endTime': json['endTime'],
      'recurrence': json['recurrence'],
      'startDate': json['startDate'],
      'endDate': null,
      'createdAt': json['createdAt'],
      'updatedAt': json['updatedAt'] ?? json['createdAt'],
      'deletedAt': json['deletedAt'] ?? target['deletedAt'],
    };
    await s.timeBlocks.put(key, jsonEncode(block));
  }

  // Plan tasks and session marks: renamed parent fields.
  await _renameField(s.planTasks, 'targetId', 'goalId');
  await _renameField(s.sessionMarks, 'actionId', 'timeBlockId');

  // Pending sync entries.
  final queue = s.syncQueue;
  if (queue != null) {
    for (final key in queue.keys) {
      final json = _decode(queue, key);
      if (json == null) continue;
      final type = switch (json['type']) {
        'target' => 'goal',
        'consistentAction' => 'timeBlock',
        _ => null,
      };
      if (type == null) continue;
      json['type'] = type;
      await queue.put('$type:${json['id']}', jsonEncode(json));
      await queue.delete(key);
    }
  }

  // Pull cursors of the renamed resources (every user on this device).
  final syncMeta = s.syncMeta;
  if (syncMeta != null) {
    for (final key in syncMeta.keys) {
      if (_cursorNames.any((n) => key.startsWith('${n}Cursor:'))) {
        await syncMeta.delete(key);
      }
    }
  }

  // Old boxes last, then the marker.
  for (final key in s.oldActions.keys) {
    await s.oldActions.delete(key);
  }
  for (final key in s.oldTargets.keys) {
    await s.oldTargets.delete(key);
  }
  await s.meta.put(_schemaKey, '$projectsSchemaVersion');
  return true;
}

Future<void> _renameField(StringStore store, String from, String to) async {
  for (final key in store.keys) {
    final json = _decode(store, key);
    if (json == null || !json.containsKey(from)) continue;
    final value = json.remove(from);
    json.putIfAbsent(to, () => value);
    await store.put(key, jsonEncode(json));
  }
}

Map<String, dynamic>? _decode(StringStore store, String key) {
  final raw = store.get(key);
  if (raw == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } on Object catch (e) {
    developer.log('Skipping unreadable $key: $e', name: 'ProjectsMigration');
    return null;
  }
}

/// Opens the Hive boxes and runs [migrateProjectsStorage] (`main.dart`,
/// before `HiveProjectRepository.open` and before the [syncQueue] store is
/// handed to `SyncQueue`). [boxPrefix] isolates test data. The emptied old
/// boxes are deleted from disk.
Future<bool> migrateHiveProjectsStorage({
  String boxPrefix = '',
  StringStore? syncQueue,
  StringStore? syncMeta,
}) async {
  final meta = await HiveStringStore.open('${boxPrefix}projects_meta');
  if (projectsStorageIsCurrent(meta)) return false;
  Future<HiveStringStore> open(String name) =>
      HiveStringStore.open('$boxPrefix$name');
  final stores = ProjectsStorageStores(
    meta: meta,
    oldTargets: await open('project_targets'),
    oldActions: await open('project_actions'),
    goals: await open('project_goals'),
    planTasks: await open('project_plan_tasks'),
    timeBlocks: await open('project_time_blocks'),
    sessionMarks: await open('project_session_marks'),
    syncQueue: syncQueue,
    syncMeta: syncMeta,
  );
  final ran = await migrateProjectsStorage(stores);
  for (final s in [stores.oldTargets, stores.oldActions]) {
    await s.close();
  }
  await Hive.deleteBoxFromDisk('${boxPrefix}project_targets');
  await Hive.deleteBoxFromDisk('${boxPrefix}project_actions');
  return ran;
}
