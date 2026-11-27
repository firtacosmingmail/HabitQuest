import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/features/projects/data/hive_project_repository.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:hive_ce/hive.dart';

import 'helpers.dart';

class _Recorder implements ChangeRecorder {
  final calls = <(SyncEntityType, String)>[];
  @override
  Future<void> recordChange(SyncEntityType type, String id) async =>
      calls.add((type, id));
}

ProjectRecords sample() {
  final g = goal('g1', deadline: DateTime(2026, 11, 30));
  return ProjectRecords(
    projects: [project('p1', name: 'Content business')],
    goals: [g],
    planTasks: [
      PlanTask(
        id: 'k1',
        goalId: 'g1',
        title: 'Script 1',
        deliveryDate: DateTime(2026, 11, 10),
        createdAt: createdOn(2026, 11, 1),
      ),
    ],
    timeBlocks: [
      weekly('b1', days: monFri, label: 'Editing'),
      monthly(
        'b2',
        days: {1, 15},
        start: '18:00',
        end: '19:00',
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2027, 3, 31),
      ),
    ],
    consistentActions: [
      action('c1', text: 'Post one short a day'),
      action('c2', text: 'Reply to comments', sortOrder: 1),
    ],
    sessionMarks: [
      SessionMark(
        timeBlockId: 'b1',
        date: DateTime(2026, 11, 2),
        attended: true,
        updatedAt: DateTime.utc(2026, 11, 2, 14),
      ),
    ],
  );
}

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('habit_quest_projects_hive');
    Hive.init(tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  group('HiveProjectRepository', () {
    test('uses one box per kind', () {
      expect(HiveProjectRepository.boxNames, {
        ProjectEntityKind.project: 'projects',
        ProjectEntityKind.goal: 'project_goals',
        ProjectEntityKind.planTask: 'project_plan_tasks',
        ProjectEntityKind.timeBlock: 'project_time_blocks',
        ProjectEntityKind.consistentAction: 'project_consistent_actions',
        ProjectEntityKind.sessionMark: 'project_session_marks',
      });
    });

    test('persists every kind across reopen (tombstones included)', () async {
      final s = sample();
      var repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      await repo.save(s);
      final deleted = repo
          .getProjectRecord('p1')!
          .copyWith(deletedAt: () => DateTime.utc(2026, 11, 20));
      await repo.close();

      repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      final d = repo.getData();
      expect(d.projects.single.name, 'Content business');
      expect(d.goals.single, s.goals.single);
      expect(d.planTasks.single.deliveryDate, DateTime(2026, 11, 10));
      expect(d.planTasks.single.goalId, 'g1');
      expect(d.timeBlocks, s.timeBlocks);
      expect(d.timeBlock('b1')!.label, 'Editing');
      expect(d.timeBlock('b1')!.isOpenEnded, isTrue);
      expect(d.timeBlock('b2')!.endDate, DateTime(2027, 3, 31));
      expect(d.consistentActions, s.consistentActions);
      expect(d.consistentActionsOf('g1').map((a) => a.text), [
        'Post one short a day',
        'Reply to comments',
      ]);
      expect(d.isAttended('b1', DateTime(2026, 11, 2)), isTrue);
      expect(repo.getGoalRecord('g1'), s.goals.single);
      expect(repo.getTimeBlockRecord('b2'), s.timeBlocks[1]);
      expect(repo.getConsistentActionRecord('c2'), s.consistentActions[1]);
      expect(
        repo.getSessionMarkRecord('b1', DateTime(2026, 11, 2)),
        s.sessionMarks.single,
      );

      await repo.save(ProjectRecords(projects: [deleted]));
      await repo.close();
      repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      expect(repo.getData().projects, isEmpty);
      expect(repo.getData().goals, isEmpty, reason: 'cascade hidden');
      expect(repo.getData().timeBlocks, isEmpty, reason: 'cascade hidden');
      expect(repo.getData().consistentActions, isEmpty, reason: 'cascade');
      expect(repo.getData().sessionMarks, isEmpty, reason: 'cascade hidden');
      expect(repo.getAllProjectRecords().single.isDeleted, isTrue);
      expect(repo.getAllGoalRecords(), hasLength(1));
      expect(repo.getAllPlanTaskRecords(), hasLength(1));
      expect(repo.getAllTimeBlockRecords(), hasLength(2));
      expect(repo.getAllConsistentActionRecords(), hasLength(2));
      expect(repo.getAllSessionMarkRecords(), hasLength(1));
      await repo.clearAll();
      expect(repo.getAllGoalRecords(), isEmpty);
      expect(repo.getAllConsistentActionRecords(), isEmpty);
      await repo.close();
      repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      expect(repo.getAllProjectRecords(), isEmpty);
      expect(repo.getAllTimeBlockRecords(), isEmpty);
      expect(repo.getAllConsistentActionRecords(), isEmpty);
      expect(repo.getAllSessionMarkRecords(), isEmpty);
      await repo.close();
    });

    test('a deleted goal hides its consistent actions after reopen', () async {
      var repo = await HiveProjectRepository.open(boxPrefix: 'c_');
      await repo.save(sample());
      final g = repo
          .getGoalRecord('g1')!
          .copyWith(deletedAt: () => DateTime.utc(2026, 11, 20));
      await repo.save(ProjectRecords(goals: [g]));
      await repo.close();
      repo = await HiveProjectRepository.open(boxPrefix: 'c_');
      final d = repo.getData();
      expect(d.goals, isEmpty);
      expect(d.planTasks, isEmpty);
      expect(d.consistentActions, isEmpty);
      expect(d.timeBlocks, hasLength(2), reason: 'blocks are on the project');
      expect(repo.getAllConsistentActionRecords(), hasLength(2));
      await repo.close();
    });

    test('skips unreadable entries', () async {
      final box = await Hive.openBox<String>('b_projects');
      await box.put('bad', '{not json');
      await box.close();
      final cas = await Hive.openBox<String>('b_project_consistent_actions');
      await cas.put('bad', '{"id": "c1"}');
      await cas.close();
      final repo = await HiveProjectRepository.open(boxPrefix: 'b_');
      expect(repo.getData().projects, isEmpty);
      expect(repo.getAllConsistentActionRecords(), isEmpty);
      await repo.close();
    });
  });

  group('CachedProjectRepository', () {
    test('local saves are recorded for sync, remote ones are not', () async {
      final rec = _Recorder();
      final repo = InMemoryProjectRepository(recorder: rec);
      await repo.save(sample());
      expect(rec.calls, [
        (SyncEntityType.project, 'p1'),
        (SyncEntityType.goal, 'g1'),
        (SyncEntityType.planTask, 'k1'),
        (SyncEntityType.timeBlock, 'b1'),
        (SyncEntityType.timeBlock, 'b2'),
        (SyncEntityType.consistentAction, 'c1'),
        (SyncEntityType.consistentAction, 'c2'),
        (SyncEntityType.sessionMark, 'b1|2026-11-02'),
      ]);
      rec.calls.clear();
      await repo.applyRemote(
        ProjectRecords(
          projects: [project('p2', name: 'Remote')],
          consistentActions: [action('c3', text: 'Remote')],
        ),
      );
      expect(rec.calls, isEmpty);
      expect(repo.getData().projects.map((p) => p.id), ['p1', 'p2']);
      expect(repo.getConsistentActionRecord('c3')!.text, 'Remote');
    });

    test('entity kinds map to their sync types', () {
      for (final k in ProjectEntityKind.values) {
        expect(k.syncType.name, k.name);
      }
    });

    test('watchData emits now and once per batch', () async {
      final repo = InMemoryProjectRepository();
      final seen = <ProjectsData>[];
      final sub = repo.watchData().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await repo.save(sample());
      await repo.save(const ProjectRecords());
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(2));
      expect(seen.first.projects, isEmpty);
      expect(seen.last.timeBlocks, hasLength(2));
      expect(seen.last.consistentActions, hasLength(2));
      await sub.cancel();
    });
  });
}
