import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/data/sync/sync_meta.dart';
import 'package:habit_quest/data/sync/sync_queue.dart';
import 'package:habit_quest/features/projects/data/hive_project_repository.dart';
import 'package:habit_quest/features/projects/data/projects_storage_migration.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';
import 'package:hive_ce/hive.dart';

/// Pre-rework (schema v1) JSON, as `HiveProjectRepository` wrote it.
Map<String, String> encodeAll(Map<String, Map<String, dynamic>> m) =>
    m.map((k, v) => MapEntry(k, jsonEncode(v)));

const p1 = 'p1';
final v1Targets = {
  't1': {
    'id': 't1',
    'projectId': p1,
    'title': '5 videos',
    'deadline': '2026-11-30',
    'status': 'inProgress',
    'createdAt': '2026-11-01T08:00:00.000Z',
    'updatedAt': '2026-11-02T08:00:00.000Z',
    'deletedAt': null,
  },
  't2': {
    'id': 't2',
    'projectId': p1,
    'title': 'Old target',
    'deadline': '2026-10-31',
    'status': 'done',
    'createdAt': '2026-10-01T08:00:00.000Z',
    'updatedAt': '2026-10-05T08:00:00.000Z',
    'deletedAt': '2026-10-05T08:00:00.000Z',
  },
};
final v1Actions = {
  'a1': {
    'id': 'a1',
    'targetId': 't1',
    'startTime': '10:00',
    'endTime': '13:00',
    'recurrence': {
      'type': 'weekly',
      'weekdays': [1, 2, 3, 4, 5],
    },
    'startDate': null,
    'createdAt': '2026-11-01T08:00:00.000Z',
    'updatedAt': '2026-11-03T08:00:00.000Z',
    'deletedAt': null,
  },
  // Live action of a deleted target: must stay hidden as a block.
  'a2': {
    'id': 'a2',
    'targetId': 't2',
    'startTime': '14:00',
    'endTime': '15:00',
    'recurrence': {
      'type': 'monthly',
      'monthDays': [1, 15],
    },
    'startDate': '2026-10-01',
    'createdAt': '2026-10-01T08:00:00.000Z',
    'updatedAt': '2026-10-01T08:00:00.000Z',
    'deletedAt': null,
  },
  // Orphan (unknown target): dropped.
  'a3': {
    'id': 'a3',
    'targetId': 'nope',
    'startTime': '14:00',
    'endTime': '15:00',
    'recurrence': {
      'type': 'weekly',
      'weekdays': [6],
    },
    'createdAt': '2026-10-01T08:00:00.000Z',
  },
};
final v1PlanTasks = {
  'k1': {
    'id': 'k1',
    'targetId': 't1',
    'title': 'Script',
    'deliveryDate': null,
    'done': true,
    'position': 0,
    'createdAt': '2026-11-01T08:00:00.000Z',
    'updatedAt': '2026-11-01T08:00:00.000Z',
    'deletedAt': null,
  },
};
final v1Marks = {
  'a1|2026-11-16': {
    'actionId': 'a1',
    'date': '2026-11-16',
    'attended': true,
    'updatedAt': '2026-11-16T12:00:00.000Z',
    'deletedAt': null,
  },
};

String queueEntry(String type, String id, int seq) => jsonEncode({
  'type': type,
  'id': id,
  'seq': seq,
  'queuedAt': '2026-11-16T12:00:00.000Z',
  'attempts': 0,
  'lastError': null,
});

class V1Stores {
  final meta = MemoryStringStore();
  final targets = MemoryStringStore(encodeAll(v1Targets));
  final actions = MemoryStringStore(encodeAll(v1Actions));
  final goals = MemoryStringStore();
  final planTasks = MemoryStringStore(encodeAll(v1PlanTasks));
  final timeBlocks = MemoryStringStore();
  final marks = MemoryStringStore(encodeAll(v1Marks));
  final queue = MemoryStringStore({
    'target:t1': queueEntry('target', 't1', 1),
    'consistentAction:a1': queueEntry('consistentAction', 'a1', 2),
    'sessionMark:a1|2026-11-16': queueEntry('sessionMark', 'a1|2026-11-16', 3),
    'habit:h1': queueEntry('habit', 'h1', 4),
  });
  final syncMeta = MemoryStringStore({
    'owner': 'u1',
    'habitsCursor:u1': '2026-11-16T12:00:00.000Z',
    'targetsCursor:u1': '2026-11-16T12:00:00.000Z',
    'consistent-actionsCursor:u1': '2026-11-16T12:00:00.000Z',
    'plan-tasksCursor:u1': '2026-11-16T12:00:00.000Z',
    'session-marksCursor:u1': '2026-11-16T12:00:00.000Z',
    'projectsCursor:u2': '2026-11-16T12:00:00.000Z',
  });

  ProjectsStorageStores get stores => ProjectsStorageStores(
    meta: meta,
    oldTargets: targets,
    oldActions: actions,
    goals: goals,
    planTasks: planTasks,
    timeBlocks: timeBlocks,
    sessionMarks: marks,
    syncQueue: queue,
    syncMeta: syncMeta,
  );

  Map<String, dynamic> json(MemoryStringStore s, String key) =>
      jsonDecode(s.get(key)!) as Map<String, dynamic>;
}

void main() {
  test('converts v1 data: goals, project time blocks, renamed fields', () async {
    final s = V1Stores();
    expect(await migrateProjectsStorage(s.stores), isTrue);

    // Goals: same JSON, old box emptied.
    expect(s.json(s.goals, 't1'), v1Targets['t1']);
    expect(s.json(s.goals, 't2'), v1Targets['t2']);
    expect(s.targets.data, isEmpty);
    expect(s.actions.data, isEmpty);

    // Time blocks on the target's project, labelled with its title,
    // open-ended, LWW stamps unchanged.
    final b1 = s.json(s.timeBlocks, 'a1');
    expect(b1['projectId'], p1);
    expect(b1['label'], '5 videos');
    expect(b1['endDate'], isNull);
    expect(b1.containsKey('targetId'), isFalse);
    expect(b1['updatedAt'], '2026-11-03T08:00:00.000Z');
    expect(b1['deletedAt'], isNull);
    final block = TimeBlock.fromJson(b1);
    expect(block.label, '5 videos');
    expect(block.isOpenEnded, isTrue);
    // A block of a deleted target inherits the tombstone.
    expect(s.json(s.timeBlocks, 'a2')['deletedAt'], '2026-10-05T08:00:00.000Z');
    expect(s.json(s.timeBlocks, 'a2')['updatedAt'], '2026-10-01T08:00:00.000Z');
    // Orphans are dropped.
    expect(s.timeBlocks.get('a3'), isNull);

    // Renamed parent fields; keys unchanged.
    expect(s.json(s.planTasks, 'k1')['goalId'], 't1');
    expect(s.json(s.planTasks, 'k1').containsKey('targetId'), isFalse);
    expect(s.json(s.marks, 'a1|2026-11-16')['timeBlockId'], 'a1');
    expect(s.json(s.marks, 'a1|2026-11-16').containsKey('actionId'), isFalse);

    // Queue: renamed types, other entries untouched, readable by SyncQueue.
    expect(s.queue.data.keys.toSet(), {
      'goal:t1',
      'timeBlock:a1',
      'sessionMark:a1|2026-11-16',
      'habit:h1',
    });
    final queue = SyncQueue(s.queue);
    expect(queue.entryFor(SyncEntityType.goal, 't1')?.seq, 1);
    expect(queue.entryFor(SyncEntityType.timeBlock, 'a1')?.seq, 2);
    expect(queue.entryFor(SyncEntityType.consistentAction, 'a1'), isNull);

    // Projects cursors reset (every user), others kept.
    final meta = SyncMeta(s.syncMeta);
    expect(meta.ownerUserId, 'u1');
    expect(meta.habitsCursor('u1'), isNotNull);
    for (final name in ['targets', 'consistent-actions', 'plan-tasks', 'session-marks']) {
      expect(meta.projectsCursor('u1', name), isNull, reason: name);
    }
    expect(meta.projectsCursor('u2', 'projects'), isNull);
  });

  test('idempotent: a second run does nothing, even with new data', () async {
    final s = V1Stores();
    await migrateProjectsStorage(s.stores);
    final snapshot = {
      'goals': {...s.goals.data},
      'blocks': {...s.timeBlocks.data},
      'tasks': {...s.planTasks.data},
      'marks': {...s.marks.data},
    };
    // A new-meaning consistent action queued after the migration must not
    // be renamed to a time block by a second run.
    await s.queue.put(
      'consistentAction:c1',
      queueEntry('consistentAction', 'c1', 9),
    );
    expect(await migrateProjectsStorage(s.stores), isFalse);
    expect(s.goals.data, snapshot['goals']);
    expect(s.timeBlocks.data, snapshot['blocks']);
    expect(s.planTasks.data, snapshot['tasks']);
    expect(s.marks.data, snapshot['marks']);
    expect(s.queue.get('consistentAction:c1'), isNotNull);
    expect(projectsStorageIsCurrent(s.meta), isTrue);
  });

  test('re-running after a crash before the marker converges', () async {
    final s = V1Stores();
    await migrateProjectsStorage(s.stores);
    // Simulate a crash before the marker: old boxes still full.
    await s.meta.delete('schemaVersion');
    for (final e in encodeAll(v1Targets).entries) {
      await s.targets.put(e.key, e.value);
    }
    for (final e in encodeAll(v1Actions).entries) {
      await s.actions.put(e.key, e.value);
    }
    final blocks = {...s.timeBlocks.data};
    expect(await migrateProjectsStorage(s.stores), isTrue);
    expect(s.timeBlocks.data, blocks);
    expect(s.json(s.planTasks, 'k1')['goalId'], 't1');
    expect(s.targets.data, isEmpty);
  });

  test('fresh install: nothing to convert, marker written', () async {
    final s = ProjectsStorageStores(
      meta: MemoryStringStore(),
      oldTargets: MemoryStringStore(),
      oldActions: MemoryStringStore(),
      goals: MemoryStringStore(),
      planTasks: MemoryStringStore(),
      timeBlocks: MemoryStringStore(),
      sessionMarks: MemoryStringStore(),
    );
    expect(await migrateProjectsStorage(s), isTrue);
    expect(projectsStorageIsCurrent(s.meta), isTrue);
  });

  test('Hive: old boxes are converted and loaded by the repository', () async {
    final dir = await Directory.systemTemp.createTemp('projects_migration');
    Hive.init(dir.path);
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    const prefix = 'mig_';
    Future<void> fill(String box, Map<String, String> data) async {
      final b = await Hive.openBox<String>('$prefix$box');
      await b.putAll(data);
    }

    await fill('project_targets', encodeAll(v1Targets));
    await fill('project_actions', encodeAll(v1Actions));
    await fill('project_plan_tasks', encodeAll(v1PlanTasks));
    await fill('project_session_marks', encodeAll(v1Marks));
    await fill('projects', {
      p1: jsonEncode({
        'id': p1,
        'name': 'Content business',
        'archived': false,
        'createdAt': '2026-11-01T08:00:00.000Z',
        'updatedAt': '2026-11-01T08:00:00.000Z',
        'deletedAt': null,
      }),
    });

    expect(await migrateHiveProjectsStorage(boxPrefix: prefix), isTrue);
    expect(await migrateHiveProjectsStorage(boxPrefix: prefix), isFalse);
    expect(await Hive.boxExists('${prefix}project_targets'), isFalse);
    expect(await Hive.boxExists('${prefix}project_actions'), isFalse);

    final repo = await HiveProjectRepository.open(boxPrefix: prefix);
    final data = repo.getData();
    expect(data.goals.map((g) => g.id), ['t1']);
    expect(data.timeBlocks.map((b) => b.id), ['a1']);
    expect(data.timeBlocks.single.label, '5 videos');
    expect(data.planTasksOf('t1').single.done, isTrue);
    expect(data.isAttended('a1', DateTime(2026, 11, 16)), isTrue);
    // The deleted target's block is kept as a tombstone (for sync).
    expect(repo.getTimeBlockRecord('a2')?.isDeleted, isTrue);
    await repo.close();
  });
}
