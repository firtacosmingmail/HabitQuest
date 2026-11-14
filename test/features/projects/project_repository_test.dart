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
  final t = target('t1', deadline: DateTime(2026, 11, 30));
  return ProjectRecords(
    projects: [project('p1', name: 'Content business')],
    targets: [t],
    planTasks: [
      PlanTask(
          id: 'k1',
          targetId: 't1',
          title: 'Script 1',
          deliveryDate: DateTime(2026, 11, 10),
          createdAt: createdOn(2026, 11, 1)),
    ],
    actions: [weekly('a1', days: monFri), monthly('a2', days: {1, 15}, start: '18:00', end: '19:00')],
    sessionMarks: [
      SessionMark(
          actionId: 'a1',
          date: DateTime(2026, 11, 2),
          attended: true,
          updatedAt: DateTime.utc(2026, 11, 2, 14)),
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
    test('persists every kind across reopen (tombstones included)', () async {
      var repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      await repo.save(sample());
      final deleted = repo.getProjectRecord('p1')!.copyWith(
          deletedAt: () => DateTime.utc(2026, 11, 20));
      await repo.close();

      repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      final d = repo.getData();
      expect(d.projects.single.name, 'Content business');
      expect(d.targets.single.id, 't1');
      expect(d.planTasks.single.deliveryDate, DateTime(2026, 11, 10));
      expect(d.actions.map((a) => a.id), ['a1', 'a2']);
      expect(d.isAttended('a1', DateTime(2026, 11, 2)), isTrue);

      await repo.save(ProjectRecords(projects: [deleted]));
      await repo.close();
      repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      expect(repo.getData().projects, isEmpty);
      expect(repo.getData().actions, isEmpty, reason: 'cascade hidden');
      expect(repo.getAllProjectRecords().single.isDeleted, isTrue);
      expect(repo.getAllActionRecords(), hasLength(2));
      await repo.clearAll();
      expect(repo.getAllTargetRecords(), isEmpty);
      await repo.close();
      repo = await HiveProjectRepository.open(boxPrefix: 'a_');
      expect(repo.getAllSessionMarkRecords(), isEmpty);
      await repo.close();
    });

    test('skips unreadable entries', () async {
      final box = await Hive.openBox<String>('b_projects');
      await box.put('bad', '{not json');
      await box.close();
      final repo = await HiveProjectRepository.open(boxPrefix: 'b_');
      expect(repo.getData().projects, isEmpty);
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
        (SyncEntityType.target, 't1'),
        (SyncEntityType.planTask, 'k1'),
        (SyncEntityType.consistentAction, 'a1'),
        (SyncEntityType.consistentAction, 'a2'),
        (SyncEntityType.sessionMark, 'a1|2026-11-02'),
      ]);
      rec.calls.clear();
      await repo.applyRemote(
          ProjectRecords(projects: [project('p2', name: 'Remote')]));
      expect(rec.calls, isEmpty);
      expect(repo.getData().projects.map((p) => p.id), ['p1', 'p2']);
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
      expect(seen.last.actions, hasLength(2));
      await sub.cancel();
    });
  });
}
