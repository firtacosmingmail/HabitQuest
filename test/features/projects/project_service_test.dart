import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/domain/overlap.dart';
import 'package:habit_quest/features/projects/domain/project_events.dart';
import 'package:habit_quest/features/projects/domain/project_service.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/target.dart';

import 'helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  late InMemoryProjectRepository repo;
  late ProjectService service;
  late DateTime now;
  late List<ProjectChangeEvent> events;
  late List<ProjectChangeEvent> remote;
  late List<SessionAttendanceEvent> attendance;
  var ids = 0;

  setUp(() {
    ids = 0;
    now = DateTime(2026, 11, 14, 9); // Saturday
    repo = InMemoryProjectRepository();
    service = ProjectService(repo, now: () => now, idGenerator: () => 'id${++ids}');
    events = [];
    remote = [];
    attendance = [];
    service.changes.listen(events.add);
    service.remoteChanges.listen(remote.add);
    service.attendanceEvents.listen(attendance.add);
  });

  tearDown(() => service.dispose());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  /// The spec example: "Content business" / "5 videos" by 30 Nov, a 5-step
  /// plan and Mon–Fri 10–13.
  Future<(String, Target, ConsistentAction)> example() async {
    final p = await service.createProject(name: '  Content business ');
    final t = await service.createTarget(
        projectId: p.id, title: '5 videos', deadline: d(2026, 11, 30));
    for (final s in ['scripts', 'recordings', 'edits']) {
      await service.addPlanTask(targetId: t.id, title: '5 $s');
    }
    final a = await service.createAction(
      targetId: t.id,
      startTime: hm('10:00'),
      endTime: hm('13:00'),
      recurrence: WeeklyRecurrence(monFri),
    );
    await flush();
    return (p.id, t, a);
  }

  group('projects', () {
    test('create trims, stamps and emits', () async {
      final p = await service.createProject(name: '  Content business ');
      await flush();
      expect(p.name, 'Content business');
      expect(p.id, 'id1');
      expect(p.updatedAt, now.toUtc());
      expect(events.single.type, ProjectChangeType.created);
      expect(events.single.kind, ProjectEntityKind.project);
      expect(service.data.projects.single, p);
    });

    test('empty names are rejected', () {
      expect(() => service.createProject(name: '  '), throwsArgumentError);
    });

    test('rename / archive / unarchive; unchanged emits nothing', () async {
      final p = await service.createProject(name: 'A');
      now = now.add(const Duration(minutes: 1));
      final r = await service.renameProject(p.id, 'B');
      expect(r.updatedAt.isAfter(p.updatedAt), isTrue);
      await service.archiveProject(p.id);
      await service.archiveProject(p.id, archived: false);
      await service.renameProject(p.id, 'B');
      await flush();
      expect(events.map((e) => e.type), [
        ProjectChangeType.created,
        ProjectChangeType.updated,
        ProjectChangeType.archived,
        ProjectChangeType.unarchived,
      ]);
    });

    test('delete cascades tombstones to targets, tasks and actions', () async {
      final (pid, t, a) = await example();
      events.clear();
      now = now.add(const Duration(hours: 1));
      await service.deleteProject(pid);
      await flush();
      expect(service.data.projects, isEmpty);
      expect(service.data.targets, isEmpty);
      expect(repo.getAllPlanTaskRecords().every((x) => x.isDeleted), isTrue);
      expect(repo.getActionRecord(a.id)!.deletedAt, now.toUtc());
      expect(events.map((e) => e.kind), [
        ProjectEntityKind.consistentAction,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.target,
        ProjectEntityKind.project,
      ]);
      expect(events.every((e) => e.type == ProjectChangeType.deleted), isTrue);
      expect(() => service.renameProject(pid, 'x'), throwsStateError);
      expect(t.isDeleted, isFalse);
    });
  });

  group('targets', () {
    test('needs a live project; status is manual and kept', () async {
      expect(
          () => service.createTarget(
              projectId: 'nope', title: 'x', deadline: d(2026, 12, 1)),
          throwsStateError);
      final (_, t, _) = await example();
      expect(t.status, TargetStatus.notStarted);
      // Checking off every task does not change the status.
      for (final k in service.data.planTasksOf(t.id)) {
        await service.setPlanTaskDone(k.id, true);
      }
      expect(service.data.target(t.id)!.status, TargetStatus.notStarted);
      final s = await service.setTargetStatus(t.id, TargetStatus.inProgress);
      expect(s.status, TargetStatus.inProgress);
    });

    test('delete cascades to its tasks and actions only', () async {
      final (pid, t, _) = await example();
      final other = await service.createTarget(
          projectId: pid, title: 'Other', deadline: d(2026, 12, 31));
      await service.deleteTarget(t.id);
      expect(service.data.targets, [other]);
      expect(service.data.planTasks, isEmpty);
      expect(service.data.actions, isEmpty);
    });

    test('a later deadline that creates a clash is blocked', () async {
      final (pid, t, _) = await example();
      final t2 = await service.createTarget(
          projectId: pid, title: 'Course', deadline: d(2026, 12, 31));
      // Starts on 1 Dec: no clash with the 30 Nov target.
      await service.createAction(
        targetId: t2.id,
        startTime: hm('11:00'),
        endTime: hm('12:00'),
        recurrence: WeeklyRecurrence({1}),
        startDate: d(2026, 12, 1),
      );
      expect(
        () => service.updateTarget(t.copyWith(deadline: d(2026, 12, 15))),
        throwsA(isA<ActionOverlapException>()
            .having((e) => e.clashes.single.target.title, 'target', 'Course')
            .having((e) => e.clashes.single.firstDate, 'first', d(2026, 12, 7))),
      );
      expect(service.data.target(t.id)!.deadline, d(2026, 11, 30));
      // Shortening is fine.
      await service.updateTarget(t.copyWith(deadline: d(2026, 11, 20)));
    });

    test('reopening a done target that would clash is blocked', () async {
      final (pid, t, _) = await example();
      await service.setTargetStatus(t.id, TargetStatus.done);
      final t2 = await service.createTarget(
          projectId: pid, title: 'Other', deadline: d(2026, 11, 30));
      // Allowed: actions of done targets are ignored.
      await service.createAction(
        targetId: t2.id,
        startTime: hm('12:00'),
        endTime: hm('14:00'),
        recurrence: WeeklyRecurrence(monFri),
      );
      expect(() => service.setTargetStatus(t.id, TargetStatus.inProgress),
          throwsA(isA<ActionOverlapException>()));
      expect(service.data.target(t.id)!.status, TargetStatus.done);
    });
  });

  group('plan tasks', () {
    test('appended in order, editable, reorderable, deletable', () async {
      final (_, t, _) = await example();
      final tasks = service.data.planTasksOf(t.id);
      expect(tasks.map((x) => x.title), ['5 scripts', '5 recordings', '5 edits']);
      expect(tasks.map((x) => x.position), [0, 1, 2]);
      await service.updatePlanTask(
          tasks[0].copyWith(deliveryDate: () => d(2026, 11, 10)));
      expect(service.data.planTask(tasks[0].id)!.deliveryDate, d(2026, 11, 10));
      await service.reorderPlanTasks(t.id, [tasks[2].id, tasks[0].id, tasks[1].id]);
      expect(service.data.planTasksOf(t.id).map((x) => x.title),
          ['5 edits', '5 scripts', '5 recordings']);
      expect(() => service.reorderPlanTasks(t.id, [tasks[0].id]),
          throwsArgumentError);
      await service.deletePlanTask(tasks[1].id);
      expect(service.data.planTasksOf(t.id), hasLength(2));
      expect(() => service.setPlanTaskDone(tasks[1].id, true), throwsStateError);
    });
  });

  group('consistent actions', () {
    test('a target can have several non-overlapping actions', () async {
      final (_, t, _) = await example();
      final sat = await service.createAction(
        targetId: t.id,
        startTime: hm('09:00'),
        endTime: hm('11:00'),
        recurrence: WeeklyRecurrence({6}),
      );
      expect(service.data.actionsOf(t.id), hasLength(2));
      expect(sat.effectiveStartDate, d(2026, 11, 14));
    });

    test('an overlapping action is blocked with a clear message', () async {
      final (pid, _, a) = await example();
      final p2 = await service.createProject(name: 'Fitness');
      final t2 = await service.createTarget(
          projectId: p2.id, title: 'Run', deadline: d(2026, 12, 31));
      await flush();
      events.clear();
      try {
        await service.createAction(
          targetId: t2.id,
          startTime: hm('12:30'),
          endTime: hm('13:30'),
          recurrence: WeeklyRecurrence({2, 4}),
        );
        fail('expected an overlap');
      } on ActionOverlapException catch (e) {
        expect(e.clashes.single.action.id, a.id);
        expect(e.clashes.single.firstDate, d(2026, 11, 17));
        expect(e.message,
            'This time block (Tue, Thu 12:30–13:30) overlaps "5 videos" '
            '(Content business), Mon–Fri 10:00–13:00, first on 2026-11-17');
      }
      await flush();
      expect(events, isEmpty);
      expect(service.data.actionsOf(t2.id), isEmpty);
      // Touching the end is fine.
      await service.createAction(
        targetId: t2.id,
        startTime: hm('13:00'),
        endTime: hm('14:00'),
        recurrence: WeeklyRecurrence({2, 4}),
      );
      expect(pid, isNotEmpty);
    });

    test('update re-checks overlaps but ignores itself', () async {
      final (_, t, a) = await example();
      final b = await service.createAction(
        targetId: t.id,
        startTime: hm('14:00'),
        endTime: hm('15:00'),
        recurrence: WeeklyRecurrence(monFri),
      );
      await service.updateAction(a.copyWith(endTime: hm('14:00')));
      expect(() => service.updateAction(b.copyWith(startTime: hm('13:30'))),
          throwsA(isA<ActionOverlapException>()));
      expect(service.clashesFor(b.copyWith(startTime: hm('13:30'))),
          hasLength(1));
      expect(() => service.createAction(
            targetId: t.id,
            startTime: hm('15:00'),
            endTime: hm('15:00'),
            recurrence: WeeklyRecurrence({1}),
          ), throwsArgumentError);
    });

    test('a deleted action no longer blocks', () async {
      final (_, t, a) = await example();
      await service.deleteAction(a.id);
      await service.createAction(
        targetId: t.id,
        startTime: hm('10:00'),
        endTime: hm('13:00'),
        recurrence: WeeklyRecurrence(monFri),
      );
      expect(service.data.actionsOf(t.id), hasLength(1));
    });
  });

  group('sessions', () {
    test('mark attended today or in the past, not in the future', () async {
      now = DateTime(2026, 11, 16, 12); // Monday
      final (pid, t, a) = await example();
      await service.setSessionAttended(a.id, d(2026, 11, 16), true);
      await flush();
      expect(service.isAttended(a.id, d(2026, 11, 16)), isTrue);
      expect(attendance.single,
          SessionAttendanceEvent(
              actionId: a.id,
              targetId: t.id,
              projectId: pid,
              date: d(2026, 11, 16),
              attended: true));
      // Idempotent.
      await service.setSessionAttended(a.id, d(2026, 11, 16), true);
      await flush();
      expect(attendance, hasLength(1));
      expect(await service.toggleSessionAttended(a.id, d(2026, 11, 16)), isFalse);
      expect(repo.getSessionMarkRecord(a.id, d(2026, 11, 16))!.attended, isFalse);
      expect(() => service.setSessionAttended(a.id, d(2026, 11, 17), true),
          throwsArgumentError, reason: 'future');
      expect(() => service.setSessionAttended(a.id, d(2026, 11, 15), true),
          throwsArgumentError, reason: 'Sunday: no session');
      expect(() => service.setSessionAttended('nope', d(2026, 11, 16), true),
          throwsStateError);
    });
  });

  group('sync hooks', () {
    test('applyRemote announces on remoteChanges only, no attendance', () async {
      final (pid, t, a) = await example();
      events.clear();
      final renamed = service.data.project(pid)!.copyWith(
          name: 'Renamed', updatedAt: DateTime.utc(2026, 12, 1));
      final gone = a.copyWith(
          updatedAt: DateTime.utc(2026, 12, 1),
          deletedAt: () => DateTime.utc(2026, 12, 1));
      final fresh = target('t9', projectId: pid, deadline: d(2027, 1, 1));
      await service.applyRemote(ProjectRecords(
          projects: [renamed], targets: [fresh], actions: [gone]));
      await flush();
      expect(events, isEmpty);
      expect(attendance, isEmpty);
      expect(remote.map((e) => (e.kind, e.type)), [
        (ProjectEntityKind.project, ProjectChangeType.updated),
        (ProjectEntityKind.target, ProjectChangeType.created),
        (ProjectEntityKind.consistentAction, ProjectChangeType.deleted),
      ]);
      expect(service.data.project(pid)!.name, 'Renamed');
      expect(service.data.actionsOf(t.id), isEmpty);
    });

    test('clearLocalData wipes and announces deletions', () async {
      await example();
      await service.clearLocalData();
      await flush();
      expect(service.data.projects, isEmpty);
      expect(repo.getAllProjectRecords(), isEmpty);
      expect(remote.every((e) => e.type == ProjectChangeType.deleted), isTrue);
      expect(remote, hasLength(6));
    });
  });
}
